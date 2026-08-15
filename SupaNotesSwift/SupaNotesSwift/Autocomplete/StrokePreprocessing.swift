import Foundation

let RESAMPLE_STEP: Float = 0.02
let MAX_SEQ_LEN = 2048
let FEATURE_DIM = 6

struct StrokePoint {
  let x: Float
  let y: Float
  let t: Float
}

func normalizeStrokes(_ strokes: [[StrokePoint]]) -> [[StrokePoint]] {
  guard !strokes.isEmpty else {
    return strokes
  }

  var minX: Float = .greatestFiniteMagnitude
  var minY: Float = .greatestFiniteMagnitude
  var maxX: Float = -.greatestFiniteMagnitude
  var maxY: Float = -.greatestFiniteMagnitude
  var minT: Float = .greatestFiniteMagnitude
  var maxT: Float = -.greatestFiniteMagnitude

  for stroke in strokes {
    for p in stroke {
      minX = min(minX, p.x)
      maxX = max(maxX, p.x)
      minY = min(minY, p.y)
      maxY = max(maxY, p.y)
      minT = min(minT, p.t)
      maxT = max(maxT, p.t)
    }
  }

  let rangeX = maxX - minX
  let rangeY = maxY - minY
  var scale = max(rangeX, rangeY)
  if scale < 1e-6 {
    scale = 1.0
  }
  let centerX = (minX + maxX) / 2.0
  let centerY = (minY + maxY) / 2.0

  var tRange = maxT - minT
  if tRange < 1e-6 {
    tRange = 1.0
  }

  return strokes.map { stroke in
    stroke.map { p in
      StrokePoint(
        x: (p.x - centerX) / scale,
        y: (p.y - centerY) / scale,
        t: (p.t - minT) / tRange
      )
    }
  }
}

func resampleStroke(_ stroke: [StrokePoint], step: Float = RESAMPLE_STEP) -> [StrokePoint] {
  guard stroke.count >= 2 else {
    return stroke
  }

  var cumLen = [Float](repeating: 0, count: stroke.count)
  for i in 1..<stroke.count {
    let dx = stroke[i].x - stroke[i - 1].x
    let dy = stroke[i].y - stroke[i - 1].y
    cumLen[i] = cumLen[i - 1] + sqrt(dx * dx + dy * dy)
  }
  let totalLen = cumLen.last!

  if totalLen < 1e-8 {
    return [stroke[0]]
  }

  let nPoints = max(2, Int(ceil(totalLen / step)) + 1)
  var result = [StrokePoint]()
  result.reserveCapacity(nPoints)

  let xs = stroke.map { $0.x }
  let ys = stroke.map { $0.y }
  let ts = stroke.map { $0.t }

  for i in 0..<nPoints {
    let targetLen = totalLen * Float(i) / Float(nPoints - 1)
    let interpX = linearInterp(cumLen, xs, at: targetLen)
    let interpY = linearInterp(cumLen, ys, at: targetLen)
    let interpT = linearInterp(cumLen, ts, at: targetLen)
    result.append(StrokePoint(x: interpX, y: interpY, t: interpT))
  }

  return result
}

private func linearInterp(_ keys: [Float], _ values: [Float], at target: Float) -> Float {
  if target <= keys[0] {
    return values[0]
  }
  if target >= keys[keys.count - 1] {
    return values[values.count - 1]
  }

  var lo = 0
  var hi = keys.count - 1
  while lo < hi - 1 {
    let mid = (lo + hi) / 2
    if keys[mid] <= target {
      lo = mid
    } else {
      hi = mid
    }
  }

  let frac = (target - keys[lo]) / max(keys[hi] - keys[lo], 1e-10)
  return values[lo] + frac * (values[hi] - values[lo])
}

func extractPointFeatures(_ strokes: [[StrokePoint]]) -> [Float] {
  var allFeatures = [Float]()

  for (i, stroke) in strokes.enumerated() {
    let resampled = resampleStroke(stroke)
    let n = resampled.count

    for j in 0..<n {
      let x = resampled[j].x
      let y = resampled[j].y
      var dx: Float = 0
      var dy: Float = 0
      var dt: Float = 0
      var penState: Float = 0

      if j > 0 {
        dx = resampled[j].x - resampled[j - 1].x
        dy = resampled[j].y - resampled[j - 1].y
        dt = resampled[j].t - resampled[j - 1].t
      }

      if j == 0 && i > 0 {
        penState = 1.0
      }

      allFeatures.append(contentsOf: [x, y, dx, dy, dt, penState])
    }
  }

  let maxFloats = MAX_SEQ_LEN * FEATURE_DIM
  if allFeatures.count > maxFloats {
    allFeatures = Array(allFeatures.prefix(maxFloats))
  }

  return allFeatures
}
