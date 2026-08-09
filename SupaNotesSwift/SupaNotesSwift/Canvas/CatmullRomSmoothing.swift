import CoreGraphics

func catmullRomPath(from points: [CGPoint]) -> CGPath {
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

  let segments = 8
  let lastIndex = points.count - 1

  for i in 0..<lastIndex {
    let p0 = points[max(i - 1, 0)]
    let p1 = points[i]
    let p2 = points[min(i + 1, lastIndex)]
    let p3 = points[min(i + 2, lastIndex)]

    for s in 1...segments {
      let t = CGFloat(s) / CGFloat(segments)
      let t2 = t * t
      let t3 = t2 * t

      let x =
        0.5
        * ((2 * p1.x)
          + (-p0.x + p2.x) * t
          + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2
          + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3)

      let y =
        0.5
        * ((2 * p1.y)
          + (-p0.y + p2.y) * t
          + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2
          + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)

      path.addLine(to: CGPoint(x: x, y: y))
    }
  }

  return path
}
