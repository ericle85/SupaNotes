import CoreGraphics
import Foundation

func findEqualSignCenter(strokeBounds: [CGRect]) -> CGPoint? {
  var horizontals: [(midX: CGFloat, midY: CGFloat, width: CGFloat)] = []

  for bounds in strokeBounds {
    let xRange = bounds.width
    let yRange = bounds.height
    if xRange > 3.0 && yRange / (xRange + 0.01) < 0.4 {
      horizontals.append((midX: bounds.midX, midY: bounds.midY, width: xRange))
    }
  }

  var bestPair: CGPoint? = nil
  var bestXDist: CGFloat = .greatestFiniteMagnitude

  for i in 0..<horizontals.count {
    for j in (i + 1)..<horizontals.count {
      let a = horizontals[i]
      let b = horizontals[j]
      let xDist = abs(a.midX - b.midX)
      let yDist = abs(a.midY - b.midY)
      let widthRatio = min(a.width, b.width) / max(a.width, b.width)
      if widthRatio > 0.5 && xDist < 10.0 && yDist > 2.0 && yDist < 12.0 && xDist < bestXDist {
        bestXDist = xDist
        bestPair = CGPoint(x: (a.midX + b.midX) / 2, y: (a.midY + b.midY) / 2)
      }
    }
  }

  return bestPair
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
  let heights = strokeBounds.compactMap { bounds -> CGFloat? in
    let h = bounds.height
    if h > 1.0 {
      return h
    }
    return nil
  }
  if heights.isEmpty {
    return 20.0
  }
  let sorted = heights.sorted()
  let idx = Int(Double(sorted.count) * 0.5)
  return sorted[min(idx, sorted.count - 1)]
}
