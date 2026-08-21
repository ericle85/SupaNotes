import iosMath
import UIKit

extension MathSuggestionOverlay {
    func showAppended(suggestion: String, at point: CGPoint, fontSize: CGFloat) {
        let label = makeMathLabel(latex: suggestion, fontSize: fontSize)
        let size = label.intrinsicContentSize
        label.frame = CGRect(x: point.x, y: point.y - size.height / 2,
                             width: size.width, height: size.height)
        addSubview(label)
        currentMathLabels = [label]
    }

    func showAligned(suggestion: String, equalCenter: CGPoint,
                     fontSize: CGFloat, strokesBBox: CGRect)
    {
        guard let index = suggestion.firstIndex(of: "=") else {
            showAppended(suggestion: suggestion, at: equalCenter, fontSize: fontSize)
            return
        }
        let prefix = String(suggestion[..<index])
        let suffix = String(suggestion[suggestion.index(after: index)...])
        let equal = makeMathLabel(latex: "=", fontSize: fontSize)
        let equalSize = equal.intrinsicContentSize
        var prefixLabel: MTMathUILabel?
        if !prefix.isEmpty {
            prefixLabel = makeMathLabel(latex: prefix, fontSize: fontSize)
        }

        var suffixLabel: MTMathUILabel?
        if !suffix.isEmpty {
            suffixLabel = makeMathLabel(latex: suffix, fontSize: fontSize)
        }
        let labels = [equal] + [prefixLabel, suffixLabel].compactMap { $0 }
        let height = labels.map(\.intrinsicContentSize.height).max() ?? equalSize.height
        let centerY = max(equalCenter.y, strokesBBox.maxY + 8 + height / 2)
        equal.frame = CGRect(x: equalCenter.x - equalSize.width / 2,
                             y: centerY - equalSize.height / 2,
                             width: equalSize.width, height: equalSize.height)
        addSubview(equal)
        if let label = prefixLabel {
            let size = label.intrinsicContentSize
            label.frame = CGRect(x: equal.frame.minX - size.width, y: centerY - size.height / 2,
                                 width: size.width, height: size.height)
            addSubview(label)
        }
        if let label = suffixLabel {
            let size = label.intrinsicContentSize
            label.frame = CGRect(x: equal.frame.maxX, y: centerY - size.height / 2,
                                 width: size.width, height: size.height)
            addSubview(label)
        }
        currentMathLabels = labels
    }

    func addButtons() {
        let content = currentMathLabels.reduce(CGRect.null) { $0.union($1.frame) }
        guard !content.isNull else { return }
        let middle = content.midY - (currentMathLabels.first?.contentInsets.bottom ?? 0) / 2
        let top = middle - (buttonSize * 2 + buttonGap) / 2
        acceptIconView = addIcon(name: "checkmark", color: .systemGreen,
                                 frame: CGRect(x: content.maxX + buttonGap, y: top,
                                               width: buttonSize, height: buttonSize))
        acceptButtonFrame = acceptIconView!.frame
        denyIconView = addIcon(name: "xmark", color: .systemRed,
                               frame: CGRect(x: content.maxX + buttonGap, y: top + buttonSize + buttonGap,
                                             width: buttonSize, height: buttonSize))
        denyButtonFrame = denyIconView!.frame
    }

    private func addIcon(name: String, color: UIColor, frame: CGRect) -> UIImageView {
        let image = UIImage(systemName: name,
                            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold))
        let view = UIImageView(image: image)
        view.frame = frame
        view.tintColor = color
        view.contentMode = .center
        addSubview(view)
        return view
    }

    func makeMathLabel(latex: String, fontSize: CGFloat) -> MTMathUILabel {
        let label = MTMathUILabel()
        label.latex = latex
        label.fontSize = fontSize
        label.textColor = ghostColor
        label.backgroundColor = .clear
        label.contentInsets = MTEdgeInsets(top: 0, left: 0, bottom: fontSize * 0.15, right: 0)
        label.contentScaleFactor = contentScaleFactor * 2
        return label
    }
}
