import CoreGraphics

struct InterpolatedPoint {
  let location: CGPoint
  let force: CGFloat
}

func getInterpolatedStrokePoints(from points: [StrokePoint]) -> [InterpolatedPoint] {
  guard points.count >= 2 else {
    return points.map { InterpolatedPoint(location: $0.location, force: $0.force) }
  }

  if points.count == 2 {
    return points.map { InterpolatedPoint(location: $0.location, force: $0.force) }
  }

  var result: [InterpolatedPoint] = [
    InterpolatedPoint(location: points[0].location, force: points[0].force)
  ]

  let subdivisions = 3
  let lastIndex = points.count - 1

  for i in 0..<lastIndex {
    let p0 = points[max(i - 1, 0)]
    let p1 = points[i]
    let p2 = points[min(i + 1, lastIndex)]
    let p3 = points[min(i + 2, lastIndex)]

    for s in 1...subdivisions {
      let t = CGFloat(s) / CGFloat(subdivisions)
      let location = getCatmullRomPoint(
        p0: p0.location, p1: p1.location,
        p2: p2.location, p3: p3.location, t: t)
      let force = catmullRomScalar(
        v0: p0.force, v1: p1.force,
        v2: p2.force, v3: p3.force, t: t)
      result.append(InterpolatedPoint(location: location, force: max(force, 0)))
    }
  }

  return result
}

private func catmullRomScalar(
  v0: CGFloat, v1: CGFloat, v2: CGFloat, v3: CGFloat, t: CGFloat
) -> CGFloat {
  let t2 = t * t
  let t3 = t2 * t
  return 0.5
    * ((2 * v1)
      + (-v0 + v2) * t
      + (2 * v0 - 5 * v1 + 4 * v2 - v3) * t2
      + (-v0 + 3 * v1 - 3 * v2 + v3) * t3)
}

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

  let subdivisions = 3
  let lastIndex = points.count - 1

  for i in 0..<lastIndex {
    let p0 = points[max(i - 1, 0)]
    let p1 = points[i]
    let p2 = points[min(i + 1, lastIndex)]
    let p3 = points[min(i + 2, lastIndex)]

    for s in 1...subdivisions {
      let t = CGFloat(s) / CGFloat(subdivisions)

      let point = getCatmullRomPoint(p0: p0, p1: p1, p2: p2, p3: p3, t: t)
      path.addLine(to: point)
    }
  }

  return path
}

private func getCatmullRomPoint(p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint, t: CGFloat)
  -> CGPoint
{
  let t2 = t * t
  let t3 = t2 * t

  let calculate = { (v0: CGFloat, v1: CGFloat, v2: CGFloat, v3: CGFloat) -> CGFloat in
    0.5
      * ((2 * v1)
        + (-v0 + v2) * t
        + (2 * v0 - 5 * v1 + 4 * v2 - v3) * t2
        + (-v0 + 3 * v1 - 3 * v2 + v3) * t3)
  }

  return CGPoint(
    x: calculate(p0.x, p1.x, p2.x, p3.x),
    y: calculate(p0.y, p1.y, p2.y, p3.y)
  )
}
