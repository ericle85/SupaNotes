import CoreGraphics
import UIKit

func renderStroke(
  points: [StrokePoint],
  color: CGColor,
  baseWidth: CGFloat,
  into context: CGContext
) {
  guard let first = points.first else {
    return
  }

  if points.count == 1 {
    let w = widthForForce(first.force, baseWidth: baseWidth)
    let radius = w / 2
    context.setFillColor(color)
    context.fillEllipse(
      in: CGRect(
        x: first.location.x - radius,
        y: first.location.y - radius,
        width: w, height: w
      ))
    return
  }

  let interpolated = getInterpolatedStrokePoints(from: points)
  let widths = interpolated.map { widthForForce($0.force, baseWidth: baseWidth) }

  guard interpolated.count >= 2 else {
    return
  }

  var leftPoints: [CGPoint] = []
  var rightPoints: [CGPoint] = []

  for i in 0..<interpolated.count {
    let loc = interpolated[i].location
    let halfW = widths[i] / 2

    let dx: CGFloat
    let dy: CGFloat
    if i == 0 {
      dx = interpolated[1].location.x - loc.x
      dy = interpolated[1].location.y - loc.y
    } else if i == interpolated.count - 1 {
      dx = loc.x - interpolated[i - 1].location.x
      dy = loc.y - interpolated[i - 1].location.y
    } else {
      dx = interpolated[i + 1].location.x - interpolated[i - 1].location.x
      dy = interpolated[i + 1].location.y - interpolated[i - 1].location.y
    }

    let len = sqrt(dx * dx + dy * dy)
    let nx: CGFloat
    let ny: CGFloat
    if len < 0.0001 {
      nx = 0
      ny = 1
    } else {
      nx = -dy / len
      ny = dx / len
    }

    leftPoints.append(CGPoint(x: loc.x + nx * halfW, y: loc.y + ny * halfW))
    rightPoints.append(CGPoint(x: loc.x - nx * halfW, y: loc.y - ny * halfW))
  }

  let outline = CGMutablePath()
  outline.move(to: leftPoints[0])
  for i in 1..<leftPoints.count {
    outline.addLine(to: leftPoints[i])
  }
  for i in stride(from: rightPoints.count - 1, through: 0, by: -1) {
    outline.addLine(to: rightPoints[i])
  }
  outline.closeSubpath()

  context.setFillColor(color)
  context.addPath(outline)
  context.fillPath()

  let firstW = widths[0]
  let firstR = firstW / 2
  context.fillEllipse(
    in: CGRect(
      x: interpolated[0].location.x - firstR,
      y: interpolated[0].location.y - firstR,
      width: firstW, height: firstW
    ))
  let lastIdx = interpolated.count - 1
  let lastW = widths[lastIdx]
  let lastR = lastW / 2
  context.fillEllipse(
    in: CGRect(
      x: interpolated[lastIdx].location.x - lastR,
      y: interpolated[lastIdx].location.y - lastR,
      width: lastW, height: lastW
    ))
}

private func widthForForce(_ force: CGFloat, baseWidth: CGFloat) -> CGFloat {
  let effectiveForce = force < 0.01 ? 1.0 : force
  let normalized = min(effectiveForce / 4.0, 1.0)
  return baseWidth * (0.2 + 1.3 * normalized)
}
