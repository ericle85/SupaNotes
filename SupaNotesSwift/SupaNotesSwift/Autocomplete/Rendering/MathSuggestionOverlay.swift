import PencilKit
import UIKit
import iosMath

func strokePathBounds(_ stroke: PKStroke) -> CGRect {
  guard stroke.path.count > 0 else { return .zero }
  let points = stroke.path.map(\.location)
  let xs = points.map(\.x)
  let ys = points.map(\.y)
  return CGRect(
    x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
}

func strokesBounds(_ strokes: [PKStroke]) -> [CGRect] {
  strokes.map(strokePathBounds)
}

enum SuggestionButton {
  case accept
  case deny
}

final class MathSuggestionOverlay: UIView {
  let ghostColor = UIColor.gray.withAlphaComponent(0.5)
  let buttonSize: CGFloat = 28
  let buttonGap: CGFloat = 4
  var currentMathLabels: [MTMathUILabel] = []
  var acceptButtonFrame: CGRect = .null
  var denyButtonFrame: CGRect = .null
  var acceptIconView: UIImageView?
  var denyIconView: UIImageView?
  var onAccept: (([MTMathUILabel]) -> Void)?
  var onDeny: (() -> Void)?

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    isHidden = true
    backgroundColor = .clear
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError()
  }

  func show(
    suggestion: String, mode: String, position: CGPoint,
    strokeHeight: CGFloat, strokesBBox: CGRect
  ) {
    clearContent()
    isHidden = false
    let fontSize = strokeHeight * 1.4
    if mode == "alignWithEqualSignAbove" {
      showAligned(
        suggestion: suggestion, equalCenter: position,
        fontSize: fontSize, strokesBBox: strokesBBox)
    } else {
      showAppended(suggestion: suggestion, at: position, fontSize: fontSize)
    }
    addButtons()
  }

  func hide() {
    isHidden = true
    clearContent()
  }

  func handleAccept() {
    let labels = currentMathLabels
    currentMathLabels = []
    clearContent()
    isHidden = true
    onAccept?(labels)
  }

  func handleDeny() {
    hide()
    onDeny?()
  }

  func hitButton(at point: CGPoint) -> SuggestionButton? {
    if acceptButtonFrame.contains(point) { return .accept }
    if denyButtonFrame.contains(point) { return .deny }
    return nil
  }

  func clearContent() {
    subviews.forEach { $0.removeFromSuperview() }
    currentMathLabels = []
    acceptButtonFrame = .null
    denyButtonFrame = .null
    acceptIconView = nil
    denyIconView = nil
  }
}
