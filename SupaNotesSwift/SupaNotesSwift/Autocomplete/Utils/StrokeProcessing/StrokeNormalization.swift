import Foundation

func normalizeStrokes(_ strokes: [[StrokePoint]]) -> [[StrokePoint]] {
    guard !strokes.isEmpty else { return strokes }
    let points = strokes.flatMap { $0 }
    let minX = points.map(\.x).min() ?? 0
    let maxX = points.map(\.x).max() ?? 0
    let minY = points.map(\.y).min() ?? 0
    let maxY = points.map(\.y).max() ?? 0
    let minT = points.map(\.t).min() ?? 0
    let maxT = points.map(\.t).max() ?? 0
    let scale = max(max(maxX - minX, maxY - minY), 1e-6)
    let timeRange = max(maxT - minT, 1e-6)
    let centerX = (minX + maxX) / 2
    let centerY = (minY + maxY) / 2
    return strokes.map { stroke in
        stroke.map { point in
            StrokePoint(
                x: (point.x - centerX) / scale,
                y: (point.y - centerY) / scale,
                t: (point.t - minT) / timeRange
            )
        }
    }
}
