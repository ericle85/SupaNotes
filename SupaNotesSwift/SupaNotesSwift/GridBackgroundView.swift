import CoreGraphics
import UIKit

struct GridTheme {
    let backgroundColor: UIColor
    let majorLineColor: UIColor
    let minorLineColor: UIColor
    let majorLineWidth: CGFloat
    let minorLineWidth: CGFloat
    let majorSpacing: CGFloat
    let minorSpacing: CGFloat

    static let dark = GridTheme(
        backgroundColor: UIColor(red: 0x14/255.0, green: 0x14/255.0, blue: 0x14/255.0, alpha: 1.0),
        majorLineColor: UIColor(red: 0x20/255.0, green: 0x20/255.0, blue: 0x20/255.0, alpha: 1.0),
        minorLineColor: UIColor(red: 0x20/255.0, green: 0x20/255.0, blue: 0x20/255.0, alpha: 1.0),
        majorLineWidth: 0.5, // major & minors same for now
        minorLineWidth: 0.5, 
        majorSpacing: 100,
        minorSpacing: 25
    )
}

final class NoFadeGridTiledLayer: CATiledLayer {
    override class func fadeDuration() -> CFTimeInterval {
        return 0
    }
}

final class GridBackgroundView: UIView {
    let theme: GridTheme
    let gridSize: CGSize

    override class var layerClass: AnyClass {
        return NoFadeGridTiledLayer.self
    }

    init(theme: GridTheme, size: CGSize) {
        self.theme = theme
        self.gridSize = size
        super.init(frame: CGRect(origin: .zero, size: size))

        contentScaleFactor = 1.0
        let tiledLayer = layer as! CATiledLayer
        tiledLayer.levelsOfDetail = 4
        tiledLayer.levelsOfDetailBias = 2
        tiledLayer.tileSize = CGSize(width: 512, height: 512)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        context.setFillColor(theme.backgroundColor.cgColor)
        context.fill(rect)

        drawLines(
            in: rect,
            context: context,
            spacing: theme.minorSpacing,
            color: theme.minorLineColor.cgColor,
            lineWidth: theme.minorLineWidth
        )

        drawLines(
            in: rect,
            context: context,
            spacing: theme.majorSpacing,
            color: theme.majorLineColor.cgColor,
            lineWidth: theme.majorLineWidth
        )
    }

    private func drawLines(
        in rect: CGRect,
        context: CGContext,
        spacing: CGFloat,
        color: CGColor,
        lineWidth: CGFloat
    ) {
        context.setStrokeColor(color)
        context.setLineWidth(lineWidth)

        let firstVertical = floor(rect.minX / spacing) * spacing
        var x = firstVertical
        while x <= rect.maxX {
            context.move(to: CGPoint(x: x, y: rect.minY))
            context.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += spacing
        }

        let firstHorizontal = floor(rect.minY / spacing) * spacing
        var y = firstHorizontal
        while y <= rect.maxY {
            context.move(to: CGPoint(x: rect.minX, y: y))
            context.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += spacing
        }

        context.strokePath()
    }
}
