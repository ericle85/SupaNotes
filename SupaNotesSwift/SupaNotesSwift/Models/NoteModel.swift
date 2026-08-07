import CoreGraphics
import UIKit

struct StrokePoint {
  let location: CGPoint
  let force: CGFloat
}

struct Stroke {
  let points: [StrokePoint]
  let color: UIColor
  let width: CGFloat
}

enum PageBackground {
  case grid(GridTheme)
  case pdf(CGPDFPage)
}

struct Page {
  let background: PageBackground
  var strokes: [Stroke]

  init(background: PageBackground, strokes: [Stroke] = []) {
    self.background = background
    self.strokes = strokes
  }
}

struct Note {
  var pages: [Page]
}
