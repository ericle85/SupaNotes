import CoreGraphics

final class StrokeEngine {
    private(set) var strokes: [Stroke] = []
    private(set) var activeStroke: Stroke?

    func begin(at point: StrokePoint) {
        activeStroke = Stroke(points: [point])
    }

    func extend(with point: StrokePoint) {
        activeStroke?.points.append(point)
    }

    func end(at point: StrokePoint) {
        guard var stroke = activeStroke else { return }
        stroke.points.append(point)
        if stroke.points.count > 1 { strokes.append(stroke) }
        activeStroke = nil
    }

    func cancel() {
        activeStroke = nil
    }

    func clear() {
        strokes = []
        activeStroke = nil
    }
}
