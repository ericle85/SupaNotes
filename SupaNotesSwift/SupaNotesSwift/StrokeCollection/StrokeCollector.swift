import PencilKit
import Foundation

func convertPKStrokeToStrokePoints(_ stroke: PKStroke) -> [StrokePoint] {
    let path = stroke.path
    var points = [StrokePoint]()
    points.reserveCapacity(path.count)

    for i in 0..<path.count {
        let point = path[i]
        points.append(StrokePoint(
            x: Float(point.location.x),
            y: Float(point.location.y),
            t: Float(point.timeOffset)
        ))
    }

    return points
}

final class StrokeCollector {
    private var lastProcessedStrokeCount = 0
    private var debounceTimer: Timer?
    var onBoundingBox: ((CGRect) -> Void)?

    var drawingProvider: (() -> PKDrawing)?

    func pencilLifted() {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0,
            repeats: false
        ) { [weak self] _ in
            guard let self, let drawing = self.drawingProvider?() else { return }
            self.flushStrokes(drawing: drawing)
        }
    }

    func pencilTouched() {
        debounceTimer?.invalidate()
        debounceTimer = nil
    }

    private func flushStrokes(drawing: PKDrawing) {
        let allStrokes = drawing.strokes
        let currentCount = allStrokes.count

        if currentCount <= lastProcessedStrokeCount {
            return
        }

        let newStrokes = allStrokes[lastProcessedStrokeCount..<currentCount]
        lastProcessedStrokeCount = currentCount

        var boundingBox = CGRect.null
        for stroke in newStrokes {
            boundingBox = boundingBox.union(stroke.renderBounds)
        }
        onBoundingBox?(boundingBox)

        let converted = newStrokes.map { convertPKStrokeToStrokePoints($0) }

        DispatchQueue.global(qos: .userInitiated).async {
            runAutocompletePipeline(strokes: converted)
        }
    }
}
