import CoreGraphics
import Foundation

private struct HorizontalBar {
  let midX: CGFloat
  let midY: CGFloat
  let width: CGFloat
}

private func filterHorizontalBars(strokeBounds: [CGRect], scale: CGFloat) -> [HorizontalBar] {
  strokeBounds.compactMap { bounds in
    let normW = bounds.width / scale
    let normH = bounds.height / scale
    guard normW > 0.02, normH / (normW + 0.0001) < 0.4 else { return nil }
    return HorizontalBar(midX: bounds.midX / scale, midY: bounds.midY / scale, width: normW)
  }
}

private func isEqualSignPair(_ a: HorizontalBar, _ b: HorizontalBar) -> Bool {
  let xDist = abs(a.midX - b.midX)
  let yDist = abs(a.midY - b.midY)
  let widthRatio = min(a.width, b.width) / max(a.width, b.width)
  return widthRatio > 0.5 && xDist < 0.08 && yDist > 0.015 && yDist < 0.1
}

private func bestEqualSignPair(_ bars: [HorizontalBar]) -> (CGFloat, CGFloat)? {
  var bestPair: (CGFloat, CGFloat)? = nil
  var bestXDist: CGFloat = .greatestFiniteMagnitude
  for i in 0..<bars.count {
    for j in (i + 1)..<bars.count {
      let xDist = abs(bars[i].midX - bars[j].midX)
      guard isEqualSignPair(bars[i], bars[j]), xDist < bestXDist else { continue }
      bestXDist = xDist
      bestPair = ((bars[i].midX + bars[j].midX) / 2, (bars[i].midY + bars[j].midY) / 2)
    }
  }
  return bestPair
}

func findEqualSignCenter(strokeBounds: [CGRect]) -> CGPoint? {
  let overall = strokeBounds.reduce(CGRect.null) { $0.union($1) }
  let scale = max(max(overall.width, overall.height), 1e-6)
  let bars = filterHorizontalBars(strokeBounds: strokeBounds, scale: scale)
  guard let (nx, ny) = bestEqualSignPair(bars) else { return nil }
  return CGPoint(x: nx * scale, y: ny * scale)
}

func computeSuggestionPosition(bbox: CGRect, mode: String, strokeBounds: [CGRect]) -> CGPoint? {
  let gap: CGFloat = 8.0
  let lineHeight = bbox.height

  if mode == "append" {
    return CGPoint(x: bbox.maxX + gap, y: bbox.midY)
  }

  if mode == "below" {
    return CGPoint(x: bbox.minX, y: bbox.maxY + lineHeight * 0.5)
  }

  if mode == "alignWithEqualSignAbove" {
    let equalX = findEqualSignCenter(strokeBounds: strokeBounds)?.x ?? bbox.minX
    return CGPoint(x: equalX, y: bbox.maxY + lineHeight * 0.5)
  }

  return nil
}

func estimateStrokeHeight(strokeBounds: [CGRect]) -> CGFloat {
  let heights = strokeBounds.map(\.height).filter { $0 > 1.0 }.sorted()
  if heights.isEmpty {
    return 20.0
  }
  return heights[heights.count / 2]
}
