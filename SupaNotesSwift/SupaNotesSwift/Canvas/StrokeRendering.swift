import CoreGraphics
import UIKit

func renderStroke(
  points: [CGPoint],
  color: CGColor,
  width: CGFloat,
  into context: CGContext
) {
  guard let first = points.first else {
    return
  }

  if points.count == 1 {
    let radius = width / 2
    let dotRect = CGRect(
      x: first.x - radius,
      y: first.y - radius,
      width: width,
      height: width
    )
    context.setFillColor(color)
    context.fillEllipse(in: dotRect)
    return
  }

  let path = catmullRomPath(from: points)
  context.setStrokeColor(color)
  context.setLineWidth(width)
  context.setLineCap(.round)
  context.setLineJoin(.round)
  context.addPath(path)
  context.strokePath()
}
