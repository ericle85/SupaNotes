import Combine
import SwiftUI
import UIKit

final class DrawingCanvasController: ObservableObject {
    fileprivate weak var canvas: DrawingCanvas?

    func clear() {
        canvas?.clearStrokes()
    }
}

struct CanvasView: UIViewRepresentable {
    @ObservedObject var controller: DrawingCanvasController

    func makeUIView(context _: Context) -> DrawingCanvas {
        let canvas = DrawingCanvas()
        controller.canvas = canvas
        return canvas
    }

    func updateUIView(_: DrawingCanvas, context _: Context) {}
}

final class DrawingCanvas: StrokeInputSource {
    private let engine = StrokeEngine()

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
        setNeedsDisplay()
    }

    override func draw(_: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        StrokeRenderer.draw(engine.strokes, active: engine.activeStroke, in: context)
    }
}
