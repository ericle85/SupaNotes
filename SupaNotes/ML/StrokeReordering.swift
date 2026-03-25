import Foundation

/// Reorder strokes left-to-right by centroid X, but only if they are significantly
/// out of order. Preserves original timestamps.
func reorderStrokesLeftToRight(_ strokes: [[StrokePoint]]) -> [[StrokePoint]] {
    guard strokes.count > 1 else { return strokes }

    // Compute centroid X per stroke
    let centroids: [Float] = strokes.map { s in
        s.map(\.x).reduce(0, +) / Float(s.count)
    }

    // Measure how "out of order" the strokes are by counting inversions
    var inversions = 0
    let total = strokes.count
    for i in 0..<total {
        for j in (i + 1)..<total {
            if centroids[i] > centroids[j] { inversions += 1 }
        }
    }

    let maxInversions = total * (total - 1) / 2
    let inversionRatio = maxInversions > 0 ? Float(inversions) / Float(maxInversions) : 0

    // Only reorder if >30% of pairs are inverted — otherwise draw order is fine
    guard inversionRatio > 0.3 else { return strokes }

    // Sort by centroid X, preserving original timestamps
    let indexed = centroids.enumerated().sorted { $0.element < $1.element }
    return indexed.map { strokes[$0.offset] }
}
