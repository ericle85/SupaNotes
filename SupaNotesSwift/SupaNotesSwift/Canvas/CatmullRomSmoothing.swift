import CoreGraphics

func getCatmullRomPath(from points: [CGPoint]) -> CGPath {
  let path = CGMutablePath()

  guard points.count >= 2 else {
    return path
  }

  if points.count == 2 {
    path.move(to: points[0])
    path.addLine(to: points[1])
    return path
  }

  path.move(to: points[0])

  let lastIndex = points.count - 1

  for i in 0..<lastIndex {
    let p0 = points[max(i - 1, 0)]
    let p1 = points[i]
    let p2 = points[min(i + 1, lastIndex)]
    let p3 = points[min(i + 2, lastIndex)]

    let cp1 = CGPoint(
      x: p1.x + (p2.x - p0.x) / 6.0,
      y: p1.y + (p2.y - p0.y) / 6.0
    )
    let cp2 = CGPoint(
      x: p2.x - (p3.x - p1.x) / 6.0,
      y: p2.y - (p3.y - p1.y) / 6.0
    )

    path.addCurve(to: p2, control1: cp1, control2: cp2)
  }

  return path
}

