import Foundation
import PencilKit

func convertPKStrokesToStrokePoints(_ strokes: [PKStroke]) -> [[StrokePoint]] {
    let strokeGap: Float = 0.05
    var result = [[StrokePoint]]()
    var cumulativeTime: Float = 0

    for stroke in strokes {
        let path = stroke.path
        var points = [StrokePoint]()
        points.reserveCapacity(path.count)

        for i in 0 ..< path.count {
            let point = path[i]
            points.append(
                StrokePoint(
                    x: Float(point.location.x),
                    y: Float(point.location.y),
                    t: cumulativeTime + Float(point.timeOffset)
                )
            )
        }

        if let lastTime = points.last?.t {
            cumulativeTime = lastTime + strokeGap
        }
        result.append(points)
    }

    return result
}

final class StrokeCollector {
    var drawingProvider: (() -> PKDrawing)?
    var onBoundingBox: ((CGRect) -> Void)?

    func pencilLifted() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let drawing = self.drawingProvider?() else { return }
            guard let lastStroke = drawing.strokes.last else { return }

            self.onBoundingBox?(lastStroke.renderBounds)

            let converted = convertPKStrokesToStrokePoints([lastStroke])

            Task {
                await runOCRPipeline(strokes: converted)
            }
        }
    }
}
