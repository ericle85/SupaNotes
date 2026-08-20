import PencilKit
import UIKit
import iosMath

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

func strokePathBounds(_ stroke: PKStroke) -> CGRect {
  let path = stroke.path
  if path.count == 0 {
    return .zero
  }
  var minX = path[0].location.x
  var maxX = minX
  var minY = path[0].location.y
  var maxY = minY
  for idx in 1..<path.count {
    let point = path[idx].location
    if point.x < minX { minX = point.x }
    if point.x > maxX { maxX = point.x }
    if point.y < minY { minY = point.y }
    if point.y > maxY { maxY = point.y }
  }
  return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
}

func findEqualSignCenter(strokes: [PKStroke]) -> CGPoint? {
  var horizontals: [(midX: CGFloat, midY: CGFloat, width: CGFloat)] = []

  for stroke in strokes {
    let bounds = strokePathBounds(stroke)
    let xRange = bounds.width
    let yRange = bounds.height
    if xRange > 3.0 && yRange / (xRange + 0.01) < 0.4 {
      horizontals.append((midX: bounds.midX, midY: bounds.midY, width: xRange))
    }
  }

  var bestPair: CGPoint? = nil
  var bestXDist: CGFloat = .greatestFiniteMagnitude

  for i in 0..<horizontals.count {
    for j in (i + 1)..<horizontals.count {
      let a = horizontals[i]
      let b = horizontals[j]
      let xDist = abs(a.midX - b.midX)
      let yDist = abs(a.midY - b.midY)
      let widthRatio = min(a.width, b.width) / max(a.width, b.width)
      if widthRatio > 0.5 && xDist < 10.0 && yDist > 2.0 && yDist < 12.0 && xDist < bestXDist {
        bestXDist = xDist
        bestPair = CGPoint(x: (a.midX + b.midX) / 2, y: (a.midY + b.midY) / 2)
      }
    }
  }

  return bestPair
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
    let equalX = findEqualSignCenter(strokes: strokes)?.x ?? bbox.minX
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

  func show(
    suggestion: String, mode: String, position: CGPoint, strokeHeight: CGFloat, strokesBBox: CGRect
  ) {
    subviews.forEach { $0.removeFromSuperview() }
    isHidden = false

    let fontSize = strokeHeight * 1.4

    if mode == "alignWithEqualSignAbove" {
      showAligned(
        suggestion: suggestion, equalCenter: position, fontSize: fontSize, strokesBBox: strokesBBox)
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

  private func showAligned(
    suggestion: String, equalCenter: CGPoint, fontSize: CGFloat, strokesBBox: CGRect
  ) {
    guard let eqIdx = suggestion.firstIndex(of: "=") else {
      showAppended(suggestion: suggestion, at: equalCenter, fontSize: fontSize)
      return
    }

    let prefix = String(suggestion[suggestion.startIndex..<eqIdx])
    let afterEq = String(suggestion[suggestion.index(after: eqIdx)...])

    let eqLabel = makeMathLabel(latex: "=", fontSize: fontSize)
    let eqSize = eqLabel.intrinsicContentSize

    var labels: [(MTMathUILabel, CGSize)] = [(eqLabel, eqSize)]

    var prefixLabel: MTMathUILabel? = nil
    if !prefix.isEmpty {
      let label = makeMathLabel(latex: prefix, fontSize: fontSize)
      prefixLabel = label
      labels.append((label, label.intrinsicContentSize))
    }

    var suffixLabel: MTMathUILabel? = nil
    if !afterEq.isEmpty {
      let label = makeMathLabel(latex: afterEq, fontSize: fontSize)
      suffixLabel = label
      labels.append((label, label.intrinsicContentSize))
    }

    let tallestHeight = labels.map(\.1.height).max() ?? eqSize.height
    let gap: CGFloat = 8.0
    let minY = strokesBBox.maxY + gap + tallestHeight / 2
    let centerY = max(equalCenter.y, minY)

    eqLabel.frame = CGRect(
      x: equalCenter.x - eqSize.width / 2,
      y: centerY - eqSize.height / 2,
      width: eqSize.width,
      height: eqSize.height
    )
    addSubview(eqLabel)

    if let label = prefixLabel {
      let size = label.intrinsicContentSize
      label.frame = CGRect(
        x: eqLabel.frame.minX - size.width,
        y: centerY - size.height / 2,
        width: size.width,
        height: size.height
      )
      addSubview(label)
    }

    if let label = suffixLabel {
      let size = label.intrinsicContentSize
      label.frame = CGRect(
        x: eqLabel.frame.maxX,
        y: centerY - size.height / 2,
        width: size.width,
        height: size.height
      )
      addSubview(label)
    }
  }

  private func makeMathLabel(latex: String, fontSize: CGFloat) -> MTMathUILabel {
    let label = MTMathUILabel()
    label.latex = latex
    label.fontSize = fontSize
    label.textColor = ghostColor
    label.backgroundColor = .clear
    label.contentInsets = MTEdgeInsets(top: 0, left: 0, bottom: fontSize * 0.15, right: 0)
    label.contentScaleFactor = UIScreen.main.scale * 2
    return label
  }
}
