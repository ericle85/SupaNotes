import SwiftUI
import UIKit

struct CanvasView: UIViewRepresentable {
    func makeUIView(context: Context) -> CanvasUIView {
        CanvasUIView()
    }

    func updateUIView(_ uiView: CanvasUIView, context: Context) {}
}

class CanvasUIView: UIView {
    private let engine = StrokeEngine()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        engine.strokeRenderer.draw(engine.page, in: ctx)
    }
}
