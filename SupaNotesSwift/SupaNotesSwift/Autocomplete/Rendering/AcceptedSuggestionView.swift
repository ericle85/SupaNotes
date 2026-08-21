import iosMath
import UIKit

final class AcceptedSuggestionView: UIView {
    init(mathLabels: [MTMathUILabel]) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        accessibilityIdentifier = "committed-suggestion"

        var combined = CGRect.null
        for label in mathLabels {
            combined = combined.union(label.frame)
        }

        frame = combined
        for label in mathLabels {
            label.frame = CGRect(
                x: label.frame.origin.x - combined.origin.x,
                y: label.frame.origin.y - combined.origin.y,
                width: label.frame.width,
                height: label.frame.height
            )
            label.textColor = .label
            addSubview(label)
        }

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
            (view: AcceptedSuggestionView, _: UITraitCollection) in
            for case let label as MTMathUILabel in view.subviews {
                label.textColor = .label
            }
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }
}
