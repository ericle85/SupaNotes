import UIKit

class StrokeInputSource: UIView {
    var onStrokeStarted: ((StrokePoint) -> Void)?
    var onStrokeContinued: ((StrokePoint) -> Void)?
    var onStrokeFinished: ((StrokePoint) -> Void)?
    var onStrokeDiscarded: (() -> Void)?

    private var activeTouch: UITouch?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    private func countsAsDrawing(_ touch: UITouch, _ event: UIEvent?) -> Bool {
        touch.type == .pencil || (event?.modifierFlags.contains(.shift) ?? false)
    }

    private func strokePoint(from touch: UITouch) -> StrokePoint {
        StrokePoint(
            location: touch.location(in: self),
            force: touch.force > 0 ? touch.force : 1,
            azimuth: touch.azimuthAngle(in: self),
            altitude: touch.altitudeAngle
        )
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first, countsAsDrawing(touch, event) else { return }
        activeTouch = touch
        onStrokeStarted?(strokePoint(from: touch))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with _: UIEvent?) {
        guard let activeTouch, touches.contains(activeTouch) else { return }
        onStrokeContinued?(strokePoint(from: activeTouch))
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
