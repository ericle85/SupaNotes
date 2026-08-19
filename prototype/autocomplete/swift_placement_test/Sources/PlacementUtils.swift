import Foundation

struct StrokeBounds {
    let minX: Double
    let maxX: Double
    let minY: Double
    let maxY: Double

    var width: Double { maxX - minX }
    var height: Double { maxY - minY }
    var midX: Double { (minX + maxX) / 2 }
    var midY: Double { (minY + maxY) / 2 }
}

func computeStrokeBounds(_ points: [Point]) -> StrokeBounds {
    let xs = points.map(\.x)
    let ys = points.map(\.y)
    return StrokeBounds(
        minX: xs.min()!,
        maxX: xs.max()!,
        minY: ys.min()!,
        maxY: ys.max()!
    )
}

func computeOverallBBox(strokes: [[Point]]) -> StrokeBounds {
    let allPoints = strokes.flatMap { $0 }
    return computeStrokeBounds(allPoints)
}

func findEqualSignCenter(strokes: [[Point]]) -> (x: Double, y: Double)? {
    var horizontals: [(midX: Double, midY: Double, width: Double)] = []

    for stroke in strokes {
        let bounds = computeStrokeBounds(stroke)
        let xRange = bounds.width
        let yRange = bounds.height
        if xRange > 3.0 && yRange / (xRange + 0.01) < 0.4 {
            horizontals.append((midX: bounds.midX, midY: bounds.midY, width: xRange))
        }
    }

    var bestPair: (x: Double, y: Double)? = nil
    var bestXDist = Double.greatestFiniteMagnitude

    for i in 0..<horizontals.count {
        for j in (i + 1)..<horizontals.count {
            let a = horizontals[i]
            let b = horizontals[j]
            let xDist = abs(a.midX - b.midX)
            let yDist = abs(a.midY - b.midY)
            let widthRatio = min(a.width, b.width) / max(a.width, b.width)
            if widthRatio > 0.5 && xDist < 10.0 && yDist > 2.0 && yDist < 12.0 && xDist < bestXDist {
                bestXDist = xDist
                bestPair = ((a.midX + b.midX) / 2, (a.midY + b.midY) / 2)
            }
        }
    }

    return bestPair
}

func computeSuggestionPosition(
    bbox: StrokeBounds,
    mode: String,
    strokes: [[Point]]
) -> (x: Double, y: Double)? {
    let gap = 8.0
    let lineHeight = bbox.height

    if mode == "append" {
        return (bbox.maxX + gap, bbox.midY)
    }

    if mode == "below" {
        return (bbox.minX, bbox.maxY + lineHeight * 0.5)
    }

    if mode == "alignWithEqualSignAbove" {
        let equalX = findEqualSignCenter(strokes: strokes)?.x ?? bbox.minX
        return (equalX, bbox.maxY + lineHeight * 0.5)
    }

    return nil
}
