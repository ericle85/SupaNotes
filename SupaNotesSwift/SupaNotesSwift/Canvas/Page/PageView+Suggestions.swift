import iosMath
import PencilKit
import UIKit

extension PageView {
    func showSuggestion(result: PipelineResult, strokes: [PKStroke], bbox: CGRect) {
        guard let suggestion = result.suggestion else { return }
        let bounds = strokesBounds(strokes)
        guard let position = computeSuggestionPosition(
            bbox: bbox, mode: result.placement, strokeBounds: bounds
        ) else { return }
        suggestionOverlay.show(
            suggestion: suggestion, mode: result.placement, position: position,
            strokeHeight: estimateStrokeHeight(strokeBounds: bounds), strokesBBox: bbox
        )
    }

    func suggestionButtonHit(at point: CGPoint) -> Bool {
        guard !suggestionOverlay.isHidden else { return false }
        let point = convert(point, to: suggestionOverlay)
        return suggestionOverlay.acceptButtonFrame.contains(point)
            || suggestionOverlay.denyButtonFrame.contains(point)
    }

    @objc func handleSuggestionTap(_ gesture: UITapGestureRecognizer) {
        let tapPoint = gesture.location(in: self)
        if canvasView.tool is PKEraserTool { eraseCommittedSuggestion(at: tapPoint); return }
        let point = gesture.location(in: suggestionOverlay)
        if suggestionOverlay.acceptButtonFrame.contains(point) { suggestionOverlay.handleAccept() }
        if suggestionOverlay.denyButtonFrame.contains(point) { suggestionOverlay.handleDeny() }
    }

    func eraseCommittedSuggestion(at point: CGPoint) {
        guard let accepted = subviews.compactMap({ $0 as? AcceptedSuggestionView })
            .first(where: { $0.frame.contains(point) }) else { return }
        accepted.removeFromSuperview()
    }

    @objc func handleSuggestionHover(_ gesture: UIHoverGestureRecognizer) {
        guard !suggestionOverlay.isHidden else { resetHoverScale(); return }
        let point = gesture.location(in: suggestionOverlay)
        var icon: UIImageView?
        if suggestionOverlay.acceptButtonFrame.contains(point) {
            icon = suggestionOverlay.acceptIconView
        } else if suggestionOverlay.denyButtonFrame.contains(point) {
            icon = suggestionOverlay.denyIconView
        }
        if gesture.state == .ended || gesture.state == .cancelled { resetHoverScale(); return }
        guard icon !== lastHoveredIcon else { return }
        resetHoverScale()
        lastHoveredIcon = icon
        UIView.animate(withDuration: 0.15) { icon?.transform = CGAffineTransform(scaleX: 1.3, y: 1.3) }
    }

    func resetHoverScale() {
        lastHoveredIcon?.transform = .identity
        lastHoveredIcon = nil
    }

    func acceptSuggestion(mathLabels: [MTMathUILabel]) {
        addSubview(AcceptedSuggestionView(mathLabels: mathLabels))
    }

    func denySuggestion() {}
}
