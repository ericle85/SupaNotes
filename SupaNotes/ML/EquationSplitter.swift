import Foundation

struct StrokeSegment {
    let strokes: [[StrokePoint]]
}

/// Split a line's strokes into segments that fit within MAX_SEQ_LEN.
/// Strokes should already be reordered left-to-right.
func splitLineIntoSegments(_ strokes: [[StrokePoint]], maxPoints: Int = MAX_SEQ_LEN) -> [StrokeSegment] {
    guard !strokes.isEmpty else { return [] }

    // Estimate resampled point count per stroke
    let pointCounts = strokes.map { estimateResampledCount($0) }
    let totalPoints = pointCounts.reduce(0, +)

    let target = Int(Float(maxPoints) * 0.7)
    if totalPoints <= target {
        return [StrokeSegment(strokes: strokes)]
    }

    // Find X-gaps between consecutive stroke centroids
    let centroids = strokes.map { s -> Float in
        s.map(\.x).reduce(0, +) / Float(s.count)
    }

    struct GapInfo: Comparable {
        let index: Int  // split after this stroke index
        let gap: Float
        static func < (lhs: GapInfo, rhs: GapInfo) -> Bool { lhs.gap < rhs.gap }
    }

    var gaps = [GapInfo]()
    for i in 0..<(centroids.count - 1) {
        gaps.append(GapInfo(index: i, gap: centroids[i + 1] - centroids[i]))
    }

    // Greedily split: accumulate points, split at largest nearby gap when approaching target
    var segments = [StrokeSegment]()
    var start = 0
    var accumulated = 0

    for i in 0..<strokes.count {
        accumulated += pointCounts[i]
        if accumulated >= target && i < strokes.count - 1 {
            // Find best gap near this position (within ±2 strokes)
            let lo = max(start, i - 2)
            let hi = max(lo, min(strokes.count - 2, i + 2))
            var bestGapIdx = i
            var bestGap: Float = -1
            if lo <= hi {
                for g in lo...hi {
                    let gapVal = g < centroids.count - 1 ? centroids[g + 1] - centroids[g] : 0
                    if gapVal > bestGap { bestGap = gapVal; bestGapIdx = g }
                }
            }

            let splitAt = bestGapIdx + 1
            segments.append(StrokeSegment(strokes: Array(strokes[start..<splitAt])))
            start = splitAt
            accumulated = 0
        }
    }

    if start < strokes.count {
        segments.append(StrokeSegment(strokes: Array(strokes[start...])))
    }

    return segments
}

/// Estimate how many points resampleStroke would produce for a stroke.
private func estimateResampledCount(_ stroke: [StrokePoint]) -> Int {
    guard stroke.count >= 2 else { return stroke.count }
    var totalLen: Float = 0
    for i in 1..<stroke.count {
        let dx = stroke[i].x - stroke[i - 1].x
        let dy = stroke[i].y - stroke[i - 1].y
        totalLen += sqrt(dx * dx + dy * dy)
    }
    if totalLen < 1e-8 { return 1 }
    return max(2, Int(ceil(totalLen / RESAMPLE_STEP)) + 1)
}
