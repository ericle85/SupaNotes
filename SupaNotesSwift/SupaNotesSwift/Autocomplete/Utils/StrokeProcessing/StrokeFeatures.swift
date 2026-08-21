import Foundation

func extractPointFeatures(_ strokes: [[StrokePoint]]) -> [Float] {
    var features = [Float]()

    for (strokeIndex, stroke) in strokes.enumerated() {
        let points = resampleStroke(stroke)

        for pointIndex in points.indices {
            let point = points[pointIndex]

            var previous = point
            if pointIndex > 0 {
                previous = points[pointIndex - 1]
            }

            var penState: Float = 0
            if pointIndex == 0, strokeIndex > 0 {
                penState = 1
            }

            features.append(contentsOf: [
                point.x, point.y,
                point.x - previous.x, point.y - previous.y,
                point.t - previous.t, penState,
            ])
        }
    }

    let maximum = MAX_SEQ_LEN * FEATURE_DIM
    if features.count > maximum {
        return Array(features.prefix(maximum))
    }
    return features
}
