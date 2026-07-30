import Combine
import SwiftUI
import UIKit

final class DrawingCanvasController: ObservableObject {
    fileprivate weak var canvas: DrawingCanvas?
    var onStrokesChanged: (([Stroke]) -> Void)?

    func clear() {
        canvas?.clearStrokes()
    }

    func saveOCRFixture() throws -> URL {
        guard let canvas else { throw OCRFixtureExportError.invalidCanvasSize }
        return try canvas.saveOCRFixture()
    }

    fileprivate func notifyStrokesChanged() {
        guard let canvas else { return }
        onStrokesChanged?(canvas.currentStrokes)
    }
}

struct CanvasView: UIViewRepresentable {
    @ObservedObject var controller: DrawingCanvasController

    func makeUIView(context _: Context) -> DrawingCanvas {
        let canvas = DrawingCanvas()
        canvas.controller = controller
        controller.canvas = canvas
        return canvas
    }

    func updateUIView(_: DrawingCanvas, context _: Context) {}
}

final class DrawingCanvas: StrokeInputSource {
    private let engine = StrokeEngine()
    weak var controller: DrawingCanvasController?

    var currentStrokes: [Stroke] { engine.strokes }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        accessibilityIdentifier = QAID.drawCanvas

        onStrokeStarted = { [weak self] point in
            self?.engine.begin(at: point)
            self?.setNeedsDisplay()
        }
        onStrokeContinued = { [weak self] point in
            self?.engine.extend(with: point)
            self?.setNeedsDisplay()
        }
        onStrokeFinished = { [weak self] point in
            self?.engine.end(at: point)
            self?.setNeedsDisplay()
            self?.controller?.notifyStrokesChanged()
        }
        onStrokeDiscarded = { [weak self] in
            self?.engine.cancel()
            self?.setNeedsDisplay()
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    func clearStrokes() {
        engine.clear()
        resetStrokeTiming()
        setNeedsDisplay()
    }

    func saveOCRFixture() throws -> URL {
        let screenScale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 1
        return try OCRFixtureExporter.export(
            strokes: engine.strokes,
            canvasSize: bounds.size,
            screenScale: screenScale
        )
    }

    override func draw(_: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        StrokeRenderer.draw(engine.strokes, active: engine.activeStroke, in: context)
    }
}
