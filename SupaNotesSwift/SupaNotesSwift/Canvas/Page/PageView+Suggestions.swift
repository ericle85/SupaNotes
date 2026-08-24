import PencilKit
import UIKit
import iosMath

extension PageView {
  func suggestionButtonHit(at point: CGPoint) -> Bool {
    guard !suggestionOverlay.isHidden else { return false }
    let overlayPoint = convert(point, to: suggestionOverlay)
    return suggestionOverlay.hitButton(at: overlayPoint) != nil
  }

  @objc func handleSuggestionTap(_ gesture: UITapGestureRecognizer) {
    let tapPoint = gesture.location(in: self)

    if canvasView.tool is PKEraserTool {
      eraseCommittedSuggestion(at: tapPoint)
      return
    }

    let overlayPoint = gesture.location(in: suggestionOverlay)
    guard let button = suggestionOverlay.hitButton(at: overlayPoint) else { return }

    switch button {
    case .accept: suggestionOverlay.handleAccept()
    case .deny: suggestionOverlay.handleDeny()
    }
  }

  func eraseCommittedSuggestion(at point: CGPoint) {
    let accepted = subviews.first { $0 is AcceptedSuggestionView && $0.frame.contains(point) }
    accepted?.removeFromSuperview()
  }

  @objc func handleSuggestionHover(_ gesture: UIHoverGestureRecognizer) {
    guard !suggestionOverlay.isHidden else {
      resetHoverScale()
      return
    }
    if gesture.state == .ended || gesture.state == .cancelled {
      resetHoverScale()
      return
    }

    let point = gesture.location(in: suggestionOverlay)
    let icon = hoveredIcon(at: point)

    guard icon !== lastHoveredIcon else { return }
    resetHoverScale()
    lastHoveredIcon = icon
    UIView.animate(withDuration: 0.15) {
      icon?.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
    }
  }

  private func hoveredIcon(at point: CGPoint) -> UIImageView? {
    guard let button = suggestionOverlay.hitButton(at: point) else { return nil }
    switch button {
    case .accept: return suggestionOverlay.acceptIconView
    case .deny: return suggestionOverlay.denyIconView
    }
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
