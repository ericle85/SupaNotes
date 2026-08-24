import UIKit

final class TextSuggestionBox: UIView {
  private let textBox = UIView()
  private let currentTextLabel = UILabel()
  private let suggestionLabel = UILabel()
  private let acceptIcon = makeButtonIcon(name: "checkmark", color: .systemGreen)
  private let denyIcon = makeButtonIcon(name: "xmark", color: .systemRed)
  private let buttonSize: CGFloat = 14
  private let buttonGap: CGFloat = 2
  private let boxPaddingH: CGFloat = 4
  private let boxPaddingV: CGFloat = 3

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    isHidden = true
    backgroundColor = .clear
    clipsToBounds = false

    textBox.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.95)
    textBox.layer.cornerRadius = 0
    textBox.layer.borderWidth = 0.5
    textBox.layer.borderColor = UIColor.separator.cgColor

    currentTextLabel.textColor = .label
    suggestionLabel.textColor = .systemGreen

    addSubview(textBox)
    textBox.addSubview(currentTextLabel)
    textBox.addSubview(suggestionLabel)
    addSubview(acceptIcon)
    addSubview(denyIcon)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError()
  }

  func show(
    currentText: String, suggestion: String,
    rightEdgeX: CGFloat, lineYCenter: CGFloat, lineHeight: CGFloat
  ) {
    let fontSize = lineHeight * 0.5
    let font = UIFont.systemFont(ofSize: fontSize)

    currentTextLabel.font = font
    currentTextLabel.text = currentText
    currentTextLabel.sizeToFit()

    suggestionLabel.font = font
    suggestionLabel.text = suggestion
    suggestionLabel.sizeToFit()

    let textWidth = currentTextLabel.frame.width + suggestionLabel.frame.width
    let boxWidth = boxPaddingH + textWidth + boxPaddingH
    let boxContentHeight = max(currentTextLabel.frame.height, suggestionLabel.frame.height)
    let boxHeight = boxPaddingV + boxContentHeight + boxPaddingV

    let buttonsRowWidth = buttonSize + buttonGap + buttonSize
    let totalWidth = max(boxWidth, buttonsRowWidth)
    let totalHeight = buttonSize + 2 + boxHeight

    let boxRight = rightEdgeX
    let frameX = boxRight - totalWidth
    let frameY = lineYCenter - lineHeight / 2 - totalHeight - 2

    frame = CGRect(x: frameX, y: frameY, width: totalWidth, height: totalHeight)

    let boxX = totalWidth - boxWidth
    textBox.frame = CGRect(x: boxX, y: buttonSize + 2, width: boxWidth, height: boxHeight)

    let labelY = (boxHeight - currentTextLabel.frame.height) / 2
    currentTextLabel.frame.origin = CGPoint(x: boxPaddingH, y: labelY)
    suggestionLabel.frame.origin = CGPoint(
      x: currentTextLabel.frame.maxX,
      y: (boxHeight - suggestionLabel.frame.height) / 2
    )

    let buttonsX = totalWidth - buttonsRowWidth
    acceptIcon.frame = CGRect(x: buttonsX, y: 0, width: buttonSize, height: buttonSize)
    denyIcon.frame = CGRect(
      x: buttonsX + buttonSize + buttonGap, y: 0,
      width: buttonSize, height: buttonSize
    )

    isHidden = false
  }

  func hide() {
    isHidden = true
  }
}

private func makeButtonIcon(name: String, color: UIColor) -> UIImageView {
  let config = UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
  let image = UIImage(systemName: name, withConfiguration: config)
  let view = UIImageView(image: image)
  view.tintColor = color
  view.contentMode = .center
  return view
}
