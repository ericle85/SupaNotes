import UIKit

class StrokeInputSource: UIView {
    var onStrokeStarted: ((StrokePoint) -> Void)?
    var onStrokeContinued: ((StrokePoint) -> Void)?
    var onStrokeFinished: ((StrokePoint) -> Void)?
    var onStrokeDiscarded: (() -> Void)?

    private var activeTouch: UITouch?
    private var drawingSessionStartTimestamp: TimeInterval?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    func resetStrokeTiming() {
        drawingSessionStartTimestamp = nil
    }

    private func countsAsDrawing(_ touch: UITouch, _ event: UIEvent?) -> Bool {
        touch.type == .pencil || (event?.modifierFlags.contains(.shift) ?? false)
    }

    private func strokePoint(from touch: UITouch) -> StrokePoint {
        let startTimestamp = drawingSessionStartTimestamp ?? touch.timestamp
        return StrokePoint(
            location: touch.location(in: self),
            timestamp: touch.timestamp - startTimestamp,
            force: touch.force > 0 ? touch.force : 1,
            azimuth: touch.azimuthAngle(in: self),
            altitude: touch.altitudeAngle
        )
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first, countsAsDrawing(touch, event) else { return }
        activeTouch = touch
        if drawingSessionStartTimestamp == nil {
            drawingSessionStartTimestamp = touch.timestamp
        }
        onStrokeStarted?(strokePoint(from: touch))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeTouch, touches.contains(activeTouch) else { return }
        let touches = event?.coalescedTouches(for: activeTouch) ?? [activeTouch]
        touches.forEach { onStrokeContinued?(strokePoint(from: $0)) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with _: UIEvent?) {
        guard let activeTouch, touches.contains(activeTouch) else { return }
        onStrokeFinished?(strokePoint(from: activeTouch))
        self.activeTouch = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with _: UIEvent?) {
        guard let activeTouch, touches.contains(activeTouch) else { return }
        onStrokeDiscarded?()
        self.activeTouch = nil
    }
}
