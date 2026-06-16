import Foundation
import CoreGraphics

class StrokeEngine {
    var page = DrawingPage()
    private(set) var activeStroke: Stroke?
    var strokeRenderer = StrokeRenderer()

    func beginStroke(at point: StrokePoint) {}
    func extendStroke(with point: StrokePoint) {}
    func saveStroke() {}
    func cancelStroke() {}
}

struct StrokeRenderer {
    func draw(_ page: DrawingPage, in context: CGContext) {}
    func draw(_ stroke: Stroke, in context: CGContext) {}
}
