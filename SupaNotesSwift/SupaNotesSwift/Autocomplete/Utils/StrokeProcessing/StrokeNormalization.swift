import Foundation

struct StrokeBoundingBox {
  let minX: Float
  let maxX: Float
  let minY: Float
  let maxY: Float
  let minT: Float
  let maxT: Float

  var spanX: Float { max(maxX - minX, 1e-6) }
  var spanY: Float { max(maxY - minY, 1e-6) }
  var spanT: Float { max(maxT - minT, 1e-6) }
  var uniformScale: Float { max(spanX, spanY) }
  var centerX: Float { (minX + maxX) / 2 }
  var centerY: Float { (minY + maxY) / 2 }
}

func strokeBoundingBox(_ points: [StrokePoint]) -> StrokeBoundingBox {
  StrokeBoundingBox(
    minX: points.map(\.x).min() ?? 0,
    maxX: points.map(\.x).max() ?? 0,
    minY: points.map(\.y).min() ?? 0,
    maxY: points.map(\.y).max() ?? 0,
    minT: points.map(\.t).min() ?? 0,
    maxT: points.map(\.t).max() ?? 0
  )
}

func resampleToFixedLength(_ valuesX: [Float], _ valuesY: [Float], count: Int) -> (
  xs: [Float], ys: [Float]
) {
  let n = valuesX.count
  let zeros = [Float](repeating: 0, count: count)

  if n == 0 {
    return (zeros, zeros)
  }
  if n == 1 {
    let fillX = [Float](repeating: valuesX[0], count: count)
    let fillY = [Float](repeating: valuesY[0], count: count)
    return (fillX, fillY)
  }
  var xs = [Float](repeating: 0, count: count)
  var ys = [Float](repeating: 0, count: count)
  for i in 0..<count {
    let srcIdx = Float(i) / Float(count - 1) * Float(n - 1)
    let lo = Int(srcIdx)
    let hi = min(lo + 1, n - 1)
    let frac = srcIdx - Float(lo)
    xs[i] = valuesX[lo] + frac * (valuesX[hi] - valuesX[lo])
    ys[i] = valuesY[lo] + frac * (valuesY[hi] - valuesY[lo])
  }
  return (xs, ys)
}

func normalizePoint(_ point: StrokePoint, bbox: StrokeBoundingBox) -> StrokePoint {
  StrokePoint(
    x: (point.x - bbox.centerX) / bbox.uniformScale,
    y: (point.y - bbox.centerY) / bbox.uniformScale,
    t: (point.t - bbox.minT) / bbox.spanT
  )
}

func normalizeStrokes(_ strokes: [[StrokePoint]]) -> [[StrokePoint]] {
  guard !strokes.isEmpty else { return strokes }
  let allPoints = strokes.flatMap { $0 }
  let bbox = strokeBoundingBox(allPoints)

  func normalize(_ point: StrokePoint) -> StrokePoint {
    normalizePoint(point, bbox: bbox)
  }
  return strokes.map { $0.map(normalize) }
}
