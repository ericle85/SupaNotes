import CoreGraphics
import Foundation

func findEqualSignCenter(strokeBounds: [CGRect]) -> CGPoint? {
    let overall = strokeBounds.reduce(CGRect.null) { $0.union($1) }
    var scale = max(overall.width, overall.height)
    if scale < 1e-6 {
        scale = 1.0
    }

    var horizontals: [(midX: CGFloat, midY: CGFloat, width: CGFloat)] = []

    for bounds in strokeBounds {
        let normW = bounds.width / scale
        let normH = bounds.height / scale
        if normW > 0.02, normH / (normW + 0.0001) < 0.4 {
            horizontals.append((
                midX: bounds.midX / scale,
                midY: bounds.midY / scale,
                width: normW
            ))
        }
    }

    var bestPair: (CGFloat, CGFloat)? = nil
    var bestXDist: CGFloat = .greatestFiniteMagnitude

    for i in 0 ..< horizontals.count {
        for j in (i + 1) ..< horizontals.count {
            let a = horizontals[i]
            let b = horizontals[j]
            let xDist = abs(a.midX - b.midX)
            let yDist = abs(a.midY - b.midY)
            let widthRatio = min(a.width, b.width) / max(a.width, b.width)
            if widthRatio > 0.5, xDist < 0.08, yDist > 0.015, yDist < 0.1, xDist < bestXDist {
                bestXDist = xDist
                bestPair = ((a.midX + b.midX) / 2, (a.midY + b.midY) / 2)
            }
        }
    }

    guard let (nx, ny) = bestPair else {
        return nil
    }
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
