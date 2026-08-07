import CoreGraphics
import UIKit

struct GridTheme {
  let backgroundColor: UIColor
  let lineColor: UIColor
  let lineWidth: CGFloat
  let spacing: CGFloat

  static let dark = GridTheme(
    backgroundColor: UIColor(
      red: 0x14 / 255.0, green: 0x14 / 255.0, blue: 0x14 / 255.0, alpha: 1.0),
    lineColor: UIColor(red: 0x20 / 255.0, green: 0x20 / 255.0, blue: 0x20 / 255.0, alpha: 1.0),
    lineWidth: 0.5,
    spacing: 25
  )
}

final class GridBackgroundView: UIView {
  let theme: GridTheme

  override static var layerClass: AnyClass {
    return NoFadeTiledLayer.self
  }

  init(theme: GridTheme, size: CGSize) {
    self.theme = theme
    super.init(frame: CGRect(origin: .zero, size: size))

    contentScaleFactor = 1.0
    let tiledLayer = layer as! CATiledLayer
    tiledLayer.levelsOfDetail = 4
    tiledLayer.levelsOfDetailBias = 2
    tiledLayer.tileSize = CGSize(width: 512, height: 512)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError()
  }

  override func draw(_ rect: CGRect) {
    guard let context = UIGraphicsGetCurrentContext() else { return }

    context.setFillColor(theme.backgroundColor.cgColor)
    context.fill(rect)

    context.setStrokeColor(theme.lineColor.cgColor)
    context.setLineWidth(theme.lineWidth)

    let spacing = theme.spacing

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
