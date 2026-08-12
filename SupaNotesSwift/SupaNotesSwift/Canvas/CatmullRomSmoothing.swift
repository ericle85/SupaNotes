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

    let d01 = sqrt(hypot(p1.x - p0.x, p1.y - p0.y))
    let d12 = sqrt(hypot(p2.x - p1.x, p2.y - p1.y))
    let d23 = sqrt(hypot(p3.x - p2.x, p3.y - p2.y))

    let t1 = centripetalTangent(
      prev: p0, curr: p1, next: p2,
      dPrev: d01, dNext: d12
    )
    let t2 = centripetalTangent(
      prev: p1, curr: p2, next: p3,
      dPrev: d12, dNext: d23
    )

    let scale = d12 / 3.0

    let cp1 = CGPoint(
      x: p1.x + scale * t1.x,
      y: p1.y + scale * t1.y
    )
    let cp2 = CGPoint(
      x: p2.x - scale * t2.x,
      y: p2.y - scale * t2.y
    )

    path.addCurve(to: p2, control1: cp1, control2: cp2)
  }

  return path
}

private func centripetalTangent(
  prev: CGPoint, curr: CGPoint, next: CGPoint,
  dPrev: CGFloat, dNext: CGFloat
) -> CGPoint {
  if dPrev < 1e-6 && dNext < 1e-6 {
    return .zero
  }
  if dPrev < 1e-6 {
    return CGPoint(
      x: (next.x - curr.x) / dNext,
      y: (next.y - curr.y) / dNext
    )
  }
  if dNext < 1e-6 {
    return CGPoint(
      x: (curr.x - prev.x) / dPrev,
      y: (curr.y - prev.y) / dPrev
    )
  }
  let dTotal = dPrev + dNext
  return CGPoint(
    x: (next.x - curr.x) / dNext - (next.x - prev.x) / dTotal + (curr.x - prev.x) / dPrev,
    y: (next.y - curr.y) / dNext - (next.y - prev.y) / dTotal + (curr.y - prev.y) / dPrev
  )
}

