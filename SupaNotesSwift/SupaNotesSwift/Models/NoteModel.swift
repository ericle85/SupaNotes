import CoreGraphics
import PencilKit
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
  var initialDrawing: PKDrawing?

  init(
    background: PageBackground,
    strokes: [Stroke] = [],
    initialDrawing: PKDrawing? = nil
  ) {
    self.background = background
    self.strokes = strokes
    self.initialDrawing = initialDrawing
  }
}

struct Note {
  var pages: [Page]
}
