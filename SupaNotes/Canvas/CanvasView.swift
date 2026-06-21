import SwiftUI
import UIKit

struct CanvasView: UIViewRepresentable {
    func makeUIView(context _: Context) -> DrawingCanvas {
        DrawingCanvas()
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

    override func draw(_: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        StrokeRenderer.draw(engine.strokes, active: engine.activeStroke, in: context)
    }
}
