import UIKit

enum StrokeRenderer {
    static func draw(_ stroke: Stroke, in context: CGContext) {
        guard let first = stroke.points.first else { return }
        context.setStrokeColor(stroke.color.cgColor)
        context.setLineWidth(stroke.width)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.beginPath()
        context.move(to: first.location)
        stroke.points.dropFirst().forEach { context.addLine(to: $0.location) }
        context.strokePath()
    }

    static func draw(_ strokes: [Stroke], active: Stroke?, in context: CGContext) {
        (strokes + [active].compactMap { $0 }).forEach { draw($0, in: context) }
    }
}
