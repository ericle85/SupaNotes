import Foundation

struct OrientationCorrection {
    let angle: Float      // radians to rotate
    let isFlipped: Bool   // 180° flip needed
}

/// Detect if writing is flipped (upside-down iPad) or angled.
func detectOrientation(_ strokes: [[StrokePoint]]) -> OrientationCorrection {
    // Need enough strokes for reliable detection
    guard strokes.count >= 5 else { return OrientationCorrection(angle: 0, isFlipped: false) }

    // Compute centroid per stroke
    let centroids: [(Float, Float)] = strokes.map { stroke in
        let cx = stroke.map(\.x).reduce(0, +) / Float(stroke.count)
        let cy = stroke.map(\.y).reduce(0, +) / Float(stroke.count)
        return (cx, cy)
    }

    // Flip detection: median X-displacement between consecutive strokes (temporal order).
    // If negative → writing right-to-left → likely flipped 180°.
    var xDisplacements = [Float]()
    for i in 1..<centroids.count {
        xDisplacements.append(centroids[i].0 - centroids[i - 1].0)
    }
    xDisplacements.sort()
    let medianDx = xDisplacements[xDisplacements.count / 2]
    let flipped = medianDx < 0

    // Angle correction: linear regression on centroids → atan(slope)
    // Use centroids after potential flip
    let correctedCentroids: [(Float, Float)]
    if flipped {
        // After 180° flip, negate both x and y
        correctedCentroids = centroids.map { (-$0.0, -$0.1) }
    } else {
        correctedCentroids = centroids
    }

    let angle = computeBaselineAngle(correctedCentroids)

    return OrientationCorrection(
        angle: abs(angle) > 0.05 ? angle : 0, // ~3 degrees threshold
        isFlipped: flipped
    )
}

/// Apply orientation correction to all strokes.
func applyOrientationCorrection(_ strokes: [[StrokePoint]], correction: OrientationCorrection) -> [[StrokePoint]] {
    var result = strokes

    if correction.isFlipped {
        result = result.map { stroke in
            stroke.map { StrokePoint(x: -$0.x, y: -$0.y, t: $0.t) }
        }
    }

    if correction.angle != 0 {
        let cosA = cos(correction.angle)
        let sinA = sin(correction.angle)
        result = result.map { stroke in
            stroke.map { p in
                StrokePoint(
                    x: p.x * cosA + p.y * sinA,
                    y: -p.x * sinA + p.y * cosA,
                    t: p.t
                )
            }
        }
    }

    return result
}

/// Linear regression on points → baseline angle in radians.
private func computeBaselineAngle(_ points: [(Float, Float)]) -> Float {
    guard points.count >= 2 else { return 0 }
    let n = Float(points.count)
    let sumX = points.map(\.0).reduce(0, +)
    let sumY = points.map(\.1).reduce(0, +)
    let sumXY = points.map { $0.0 * $0.1 }.reduce(0, +)
    let sumX2 = points.map { $0.0 * $0.0 }.reduce(0, +)

    let denom = n * sumX2 - sumX * sumX
    guard abs(denom) > 1e-10 else { return 0 }

    let slope = (n * sumXY - sumX * sumY) / denom
    return atan(slope)
}
