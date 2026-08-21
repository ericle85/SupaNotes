import Foundation

let RESAMPLE_STEP: Float = 0.02
let MAX_SEQ_LEN = 2048
let FEATURE_DIM = 6

struct StrokePoint {
  let x: Float
  let y: Float
  let t: Float
}

func cumulativeArcLength(_ stroke: [StrokePoint]) -> [Float] {
  var cumLen = [Float](repeating: 0, count: stroke.count)
  for i in 1..<stroke.count {
    let dx = stroke[i].x - stroke[i - 1].x
    let dy = stroke[i].y - stroke[i - 1].y
    cumLen[i] = cumLen[i - 1] + sqrt(dx * dx + dy * dy)
  }
  return cumLen
}

func interpolatePoint(
  cumLen: [Float], xs: [Float], ys: [Float], ts: [Float], at targetLen: Float
) -> StrokePoint {
  StrokePoint(
    x: linearInterp(cumLen, xs, at: targetLen),
    y: linearInterp(cumLen, ys, at: targetLen),
    t: linearInterp(cumLen, ts, at: targetLen)
  )
}

func resampleStroke(_ stroke: [StrokePoint], step: Float = RESAMPLE_STEP) -> [StrokePoint] {
  guard stroke.count >= 2 else {
    return stroke
  }

  let cumLen = cumulativeArcLength(stroke)
  let totalLen = cumLen.last!

  if totalLen < 1e-8 {
    return [stroke[0]]
  }

  let nPoints = max(2, Int(ceil(totalLen / step)) + 1)
  let xs = stroke.map(\.x)
  let ys = stroke.map(\.y)
  let ts = stroke.map(\.t)

  return (0..<nPoints).map { i in
    let targetLen = totalLen * Float(i) / Float(nPoints - 1)
    return interpolatePoint(cumLen: cumLen, xs: xs, ys: ys, ts: ts, at: targetLen)
  }
}

private func binarySearchInterval(_ keys: [Float], target: Float) -> (lo: Int, hi: Int) {
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
  return (lo, hi)
}

private func linearInterp(_ keys: [Float], _ values: [Float], at target: Float) -> Float {
  if target <= keys.first! {
    return values.first!
  }
  if target >= keys.last! {
    return values.last!
  }

  let (lo, hi) = binarySearchInterval(keys, target: target)
  let frac = (target - keys[lo]) / max(keys[hi] - keys[lo], 1e-10)
  return values[lo] + frac * (values[hi] - values[lo])
}
