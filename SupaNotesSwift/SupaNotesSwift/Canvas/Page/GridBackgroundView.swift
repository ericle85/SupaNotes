import UIKit

final class GridBackgroundView: UIView {
    private let theme: GridTheme

    init(frame: CGRect, theme: GridTheme) {
        self.theme = theme
        super.init(frame: frame)
        backgroundColor = theme.backgroundColor
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        context.setStrokeColor(theme.lineColor.cgColor)
        context.setLineWidth(theme.lineWidth)

        var x = floor(rect.minX / theme.spacing) * theme.spacing
        while x <= rect.maxX {
            context.move(to: CGPoint(x: x, y: rect.minY))
            context.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += theme.spacing
        }

        var y = floor(rect.minY / theme.spacing) * theme.spacing
        while y <= rect.maxY {
            context.move(to: CGPoint(x: rect.minX, y: y))
            context.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += theme.spacing
        }

        context.strokePath()
    }
}
