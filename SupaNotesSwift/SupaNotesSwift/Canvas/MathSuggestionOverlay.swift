import iosMath
import PencilKit
import UIKit

func estimateStrokeHeight(strokes: [PKStroke]) -> CGFloat {
  let heights = strokes.compactMap { stroke -> CGFloat? in
    let h = stroke.renderBounds.height
    if h > 1.0 {
      return h
    }
    return nil
  }
  if heights.isEmpty {
    return 20.0
  }
  let sorted = heights.sorted()
  let idx = Int(Double(sorted.count) * 0.5)
  return sorted[min(idx, sorted.count - 1)]
}

func findEqualSignXCenter(strokes: [PKStroke]) -> CGFloat? {
  var horizontals: [(midX: CGFloat, midY: CGFloat)] = []

  for stroke in strokes {
    let bounds = stroke.renderBounds
    let xRange = bounds.width
    let yRange = bounds.height
    if xRange > 3.0 && yRange / (xRange + 0.01) < 0.4 {
      horizontals.append((midX: bounds.midX, midY: bounds.midY))
    }
  }

  for i in 0..<horizontals.count {
    for j in (i + 1)..<horizontals.count {
      let a = horizontals[i]
      let b = horizontals[j]
      let xDist = abs(a.midX - b.midX)
      let yDist = abs(a.midY - b.midY)
      if xDist < 10.0 && yDist > 2.0 && yDist < 12.0 {
        return (a.midX + b.midX) / 2
      }
    }
  }

  return nil
}

func computeSuggestionPosition(bbox: CGRect, mode: String, strokes: [PKStroke]) -> CGPoint? {
  let gap: CGFloat = 8.0
  let lineHeight = bbox.height

  if mode == "append" {
    return CGPoint(x: bbox.maxX + gap, y: bbox.midY)
  }

  if mode == "below" {
    return CGPoint(x: bbox.minX, y: bbox.maxY + lineHeight * 0.5)
  }

  if mode == "alignWithEqualSignAbove" {
    let equalX = findEqualSignXCenter(strokes: strokes) ?? bbox.minX
    return CGPoint(x: equalX, y: bbox.maxY + lineHeight * 0.5)
  }

  return nil
}

final class MathSuggestionOverlay: UIView {
  private let ghostColor = UIColor.gray.withAlphaComponent(0.5)

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

  func show(suggestion: String, mode: String, position: CGPoint, strokeHeight: CGFloat) {
    subviews.forEach { $0.removeFromSuperview() }
    isHidden = false

    // ponytail: 1.4 cap-height calibration, tune per iosMath font metrics
    let fontSize = strokeHeight * 1.4

    if mode == "alignWithEqualSignAbove" {
      showAligned(suggestion: suggestion, equalCenter: position, fontSize: fontSize)
    } else {
      showAppended(suggestion: suggestion, at: position, fontSize: fontSize)
    }
  }

  func hide() {
    isHidden = true
    subviews.forEach { $0.removeFromSuperview() }
  }

  private func showAppended(suggestion: String, at point: CGPoint, fontSize: CGFloat) {
    let label = makeMathLabel(latex: suggestion, fontSize: fontSize)
    let size = label.intrinsicContentSize
    label.frame = CGRect(
      x: point.x,
      y: point.y - size.height / 2,
      width: size.width,
      height: size.height
    )
    addSubview(label)
  }

  private func showAligned(suggestion: String, equalCenter: CGPoint, fontSize: CGFloat) {
    guard let eqIdx = suggestion.firstIndex(of: "=") else {
      showAppended(suggestion: suggestion, at: equalCenter, fontSize: fontSize)
      return
    }

    let prefix = String(suggestion[suggestion.startIndex..<eqIdx])
    let afterEq = String(suggestion[suggestion.index(after: eqIdx)...])

    let eqLabel = makeMathLabel(latex: "=", fontSize: fontSize)
    let eqSize = eqLabel.intrinsicContentSize
    eqLabel.frame = CGRect(
      x: equalCenter.x - eqSize.width / 2,
      y: equalCenter.y - eqSize.height / 2,
      width: eqSize.width,
      height: eqSize.height
    )
    addSubview(eqLabel)

    if !prefix.isEmpty {
      let prefixLabel = makeMathLabel(latex: prefix, fontSize: fontSize)
      let prefixSize = prefixLabel.intrinsicContentSize
      prefixLabel.frame = CGRect(
        x: eqLabel.frame.minX - prefixSize.width,
        y: equalCenter.y - prefixSize.height / 2,
        width: prefixSize.width,
        height: prefixSize.height
      )
      addSubview(prefixLabel)
    }

    if !afterEq.isEmpty {
      let suffixLabel = makeMathLabel(latex: afterEq, fontSize: fontSize)
      let suffixSize = suffixLabel.intrinsicContentSize
      suffixLabel.frame = CGRect(
        x: eqLabel.frame.maxX,
        y: equalCenter.y - suffixSize.height / 2,
        width: suffixSize.width,
        height: suffixSize.height
      )
      addSubview(suffixLabel)
    }
  }

  private func makeMathLabel(latex: String, fontSize: CGFloat) -> MTMathUILabel {
    let label = MTMathUILabel()
    label.latex = latex
    label.fontSize = fontSize
    label.textColor = ghostColor
    label.backgroundColor = .clear
    return label
  }
}
