import CoreGraphics
import UIKit

struct GridTheme {
  let backgroundColor: UIColor
  let lineColor: UIColor
  let lineWidth: CGFloat
  let spacing: CGFloat

  init(
    backgroundColor: UIColor, lineColor: UIColor, lineWidth: CGFloat = 0.5, spacing: CGFloat = 25
  ) {
    self.backgroundColor = backgroundColor
    self.lineColor = lineColor
    self.lineWidth = lineWidth
    self.spacing = spacing
  }

  static let dark = GridTheme(
    backgroundColor: UIColor(
      red: 0x14 / 255.0, green: 0x14 / 255.0, blue: 0x14 / 255.0, alpha: 1.0),
    lineColor: UIColor(red: 0x20 / 255.0, green: 0x20 / 255.0, blue: 0x20 / 255.0, alpha: 1.0)
  )

  static let light = GridTheme(
    backgroundColor: UIColor.white,
    lineColor: UIColor(red: 0x6F / 255.0, green: 0x6F / 255.0, blue: 0x6F / 255.0, alpha: 0.25)
  )
}

struct StrokePoint {
  let location: CGPoint
  let force: CGFloat
  let timestamp: TimeInterval
}

struct Stroke {
  let points: [StrokePoint]
  let color: UIColor
  let width: CGFloat

  var boundingRect: CGRect {
    guard let first = points.first else {
      return .zero
    }
    var minX = first.location.x
    var minY = first.location.y
    var maxX = minX
    var maxY = minY
    for point in points.dropFirst() {
      minX = min(minX, point.location.x)
      minY = min(minY, point.location.y)
      maxX = max(maxX, point.location.x)
      maxY = max(maxY, point.location.y)
    }
    let padding = width / 2 + 4
    return CGRect(
      x: minX - padding,
      y: minY - padding,
      width: maxX - minX + padding * 2,
      height: maxY - minY + padding * 2
    )
  }
}

enum PageBackground {
  case grid(GridTheme)
  case pdf(CGPDFPage)
}

struct Page {
  let background: PageBackground
  var strokes: [Stroke]

  init(
    background: PageBackground,
    strokes: [Stroke] = []
  ) {
    self.background = background
    self.strokes = strokes
  }
}

struct Note {
  var pages: [Page]
}
