import Foundation
import CoreGraphics

struct StrokeLine {
    let strokes: [[StrokePoint]]
    let boundingBox: CGRect
    let yCenter: Float
}

/// Segment strokes into horizontal lines via Y-centroid gap clustering.
func segmentIntoLines(_ strokes: [[StrokePoint]]) -> [StrokeLine] {
    guard !strokes.isEmpty else { return [] }
    if strokes.count == 1 {
        return [makeLine(strokes)]
    }

    // Compute centroid Y and height per stroke
    struct StrokeInfo {
        let index: Int
        let centroidY: Float
        let minY: Float
        let maxY: Float
    }

    let infos: [StrokeInfo] = strokes.enumerated().map { i, stroke in
        let ys = stroke.map(\.y)
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 0
        let cy = ys.reduce(0, +) / Float(ys.count)
        return StrokeInfo(index: i, centroidY: cy, minY: minY, maxY: maxY)
    }

    // Median stroke height for threshold
    var heights = infos.map { $0.maxY - $0.minY }.filter { $0 > 1e-6 }
    heights.sort()
    let medianHeight = heights.isEmpty ? Float(1) : heights[heights.count / 2]
    let gapThreshold = medianHeight * 0.6

    // Sort by centroid Y
    let sorted = infos.sorted { $0.centroidY < $1.centroidY }

    // Cluster by Y gap
    var lines = [[Int]]()
    var currentCluster = [sorted[0].index]

    for i in 1..<sorted.count {
        if sorted[i].centroidY - sorted[i - 1].centroidY > gapThreshold {
            lines.append(currentCluster)
            currentCluster = []
        }
        currentCluster.append(sorted[i].index)
    }
    lines.append(currentCluster)

    // Build StrokeLine for each cluster, sorted top-to-bottom
    return lines.map { indices in
        makeLine(indices.map { strokes[$0] })
    }
}

private func makeLine(_ lineStrokes: [[StrokePoint]]) -> StrokeLine {
    var minX: Float = .greatestFiniteMagnitude
    var minY: Float = .greatestFiniteMagnitude
    var maxX: Float = -.greatestFiniteMagnitude
    var maxY: Float = -.greatestFiniteMagnitude
    var sumY: Float = 0
    var count = 0

    for stroke in lineStrokes {
        for p in stroke {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
            sumY += p.y; count += 1
        }
    }

    let bbox = CGRect(
        x: CGFloat(minX), y: CGFloat(minY),
        width: CGFloat(maxX - minX), height: CGFloat(maxY - minY)
    )
    return StrokeLine(strokes: lineStrokes, boundingBox: bbox, yCenter: count > 0 ? sumY / Float(count) : 0)
}
