import Combine
import SwiftUI
import UIKit

final class PencilCanvasController: ObservableObject {
    @Published var strokeCount = 0
    @Published var lastTouchInfo = "—"
    fileprivate weak var view: PencilCanvasView?

    func clear() { view?.clearCanvas() }

    func inject(command: String) {
        let points = PencilCanvasController.parse(command)
        let normalized = points.isEmpty ? PencilCanvasController.defaultStroke : points
        #if DEBUG
        view?.injectPencilStroke(normalized: normalized)
        #endif
    }

    static let defaultStroke = [CGPoint(x: 0.2, y: 0.3), CGPoint(x: 0.8, y: 0.7)]

    static func parse(_ command: String) -> [CGPoint] {
        command.split(separator: " ").compactMap { pair in
            let xy = pair.split(separator: ",")
            guard xy.count == 2, let x = Double(xy[0]), let y = Double(xy[1]) else { return nil }
            return CGPoint(x: x, y: y)
        }
    }
}

struct PencilCanvas: UIViewRepresentable {
    @ObservedObject var controller: PencilCanvasController

    func makeUIView(context _: Context) -> PencilCanvasView {
        let view = PencilCanvasView()
        view.onStrokesChanged = { [weak controller] count in controller?.strokeCount = count }
        view.onTouchReport = { [weak controller] info in controller?.lastTouchInfo = info }
        controller.view = view
        return view
    }

    func updateUIView(_: PencilCanvasView, context _: Context) {}
}

final class PencilCanvasView: StrokeInputSource {
    var onStrokesChanged: ((Int) -> Void)?
    var onTouchReport: ((String) -> Void)?
    private let engine = StrokeEngine()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.secondarySystemBackground
        accessibilityIdentifier = QAID.drawCanvas
        isAccessibilityElement = true

        onStrokeStarted = { [weak self] point in
            self?.engine.begin(at: point)
            self?.setNeedsDisplay()
        }
        onStrokeContinued = { [weak self] point in
            self?.engine.extend(with: point)
            self?.setNeedsDisplay()
        }
        onStrokeFinished = { [weak self] point in
            guard let self else { return }
            self.engine.end(at: point)
            self.setNeedsDisplay()
            self.onStrokesChanged?(self.engine.strokes.count)
        }
        onStrokeDiscarded = { [weak self] in
            self?.engine.cancel()
            self?.setNeedsDisplay()
        }
    }

    func clearCanvas() {
        engine.clear()
        onStrokesChanged?(0)
        setNeedsDisplay()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first { reportTouch(touch, event) }
        super.touchesBegan(touches, with: event)
    }

    private func reportTouch(_ touch: UITouch, _ event: UIEvent?) {
        let kind: String
        switch touch.type {
        case .pencil: kind = "pencil"
        case .direct: kind = "direct (finger/mouse)"
        case .indirect: kind = "indirect"
        case .indirectPointer: kind = "indirectPointer"
        @unknown default: kind = "unknown"
        }
        let shift = event?.modifierFlags.contains(.shift) ?? false
        let info = "type: \(kind)\(shift ? " + shift → pencil" : "")"
        print("[PencilCanvas] \(info)")
        onTouchReport?(info)
    }

    override func draw(_: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        StrokeRenderer.draw(engine.strokes, active: engine.activeStroke, in: ctx)
    }

    #if DEBUG
    func injectPencilStroke(normalized points: [CGPoint]) {
        guard points.count >= 2, bounds.width > 0, bounds.height > 0 else { return }
        let mapped = points.map { CGPoint(x: $0.x * bounds.width, y: $0.y * bounds.height) }
        let touch = SyntheticPencilTouch(location: mapped[0], phase: .began)
        touchesBegan([touch], with: nil)
        for point in mapped.dropFirst() {
            touch.update(location: point, phase: .moved)
            touchesMoved([touch], with: nil)
        }
        touch.update(location: mapped[mapped.count - 1], phase: .ended)
        touchesEnded([touch], with: nil)
    }
    #endif
}

#if DEBUG
final class SyntheticPencilTouch: UITouch {
    private var _location: CGPoint
    private var _phase: UITouch.Phase

    init(location: CGPoint, phase: UITouch.Phase) {
        self._location = location
        self._phase = phase
        super.init()
    }

    func update(location: CGPoint, phase: UITouch.Phase) {
        _location = location
        _phase = phase
    }

    override var type: UITouch.TouchType { .pencil }
    override var phase: UITouch.Phase { _phase }
    override var force: CGFloat { 1 }
    override var maximumPossibleForce: CGFloat { 1 }
    override func location(in view: UIView?) -> CGPoint { _location }
    override func previousLocation(in view: UIView?) -> CGPoint { _location }
}
#endif
