import CoreGraphics
import PencilKit
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

enum PageBackground {
  case grid(GridTheme)
  case pdf(CGPDFPage)
}

struct Page {
  let background: PageBackground
  var drawing: PKDrawing

  init(
    background: PageBackground,
    drawing: PKDrawing = PKDrawing()
  ) {
    self.background = background
    self.drawing = drawing
  }
}
