import Combine
import SwiftUI
import UIKit

final class PencilCanvasController: ObservableObject {
    @Published var strokeCount = 0
    @Published var lastTouchInfo = "—"
    fileprivate weak var view: PencilCanvasView?

    func clear() {
        view?.clearStrokes()
    }

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

    func makeUIView(context: Context) -> PencilCanvasView {
        let view = PencilCanvasView()
        view.onStrokesChanged = { [weak controller] count in controller?.strokeCount = count }
        view.onTouchReport = { [weak controller] info in controller?.lastTouchInfo = info }
        controller.view = view
        return view
    }

    func updateUIView(_ uiView: PencilCanvasView, context: Context) {}
}

final class PencilCanvasView: UIView {
    var onStrokesChanged: ((Int) -> Void)?
    var onTouchReport: ((String) -> Void)?
    private var strokes: [[CGPoint]] = []
    private var current: [CGPoint] = []
    private var activePencilTouch: UITouch?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = UIColor.secondarySystemBackground
        accessibilityIdentifier = QAID.drawCanvas
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) { fatalError() }

    private func drawsAsPencil(_ touch: UITouch, _ event: UIEvent?) -> Bool {
        touch.type == .pencil || (event?.modifierFlags.contains(.shift) ?? false)
    }

    private func report(_ touch: UITouch, _ event: UIEvent?) {
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

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        report(touch, event)
        guard activePencilTouch == nil, drawsAsPencil(touch, event) else { return }
        activePencilTouch = touch
        current = [touch.location(in: self)]
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activePencilTouch, touches.contains(activePencilTouch) else { return }
        current.append(activePencilTouch.location(in: self))
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activePencilTouch, touches.contains(activePencilTouch) else { return }
        current.append(activePencilTouch.location(in: self))
        if !current.isEmpty { strokes.append(current) }
        current = []
        self.activePencilTouch = nil
        onStrokesChanged?(strokes.count)
        setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activePencilTouch, touches.contains(activePencilTouch) else { return }
        current = []
        self.activePencilTouch = nil
        setNeedsDisplay()
    }

    func clearStrokes() {
        strokes = []
        current = []
        onStrokesChanged?(0)
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.setStrokeColor(UIColor.systemBlue.cgColor)
        ctx.setLineWidth(3)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for stroke in strokes + [current] {
            guard let first = stroke.first else { continue }
            ctx.beginPath()
            ctx.move(to: first)
            for point in stroke.dropFirst() { ctx.addLine(to: point) }
            ctx.strokePath()
        }
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
