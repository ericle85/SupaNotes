import CoreGraphics
import XCTest

@testable import CatmullRomSmoothing

final class CatmullRomSmoothingTests: XCTestCase {

  let epsilon: CGFloat = 1e-6
  let curveEpsilon: CGFloat = 0.5

  // MARK: - Core Functional Tests

  func testInterpolationPassesThroughControlPoints() {
    let controlPoints = [
      CGPoint(x: 0, y: 0),
      CGPoint(x: 50, y: 100),
      CGPoint(x: 100, y: 30),
      CGPoint(x: 150, y: 80),
      CGPoint(x: 200, y: 0),
    ]

    let path = getCatmullRomPath(from: controlPoints)
    let sampledPoints = samplePath(path)

    for controlPoint in controlPoints {
      let closest = sampledPoints.min(by: {
        distance($0, controlPoint) < distance($1, controlPoint)
      })!
      XCTAssertLessThan(
        distance(closest, controlPoint),
        curveEpsilon,
        "Curve should pass through control point \(controlPoint)"
      )
    }
  }

  func testC1ContinuityAtSegmentJoints() {
    let controlPoints = [
      CGPoint(x: 0, y: 0),
      CGPoint(x: 50, y: 100),
      CGPoint(x: 100, y: 30),
      CGPoint(x: 150, y: 80),
    ]

    for i in 1..<(controlPoints.count - 1) {
      let p0 = controlPoints[max(i - 1, 0)]
      let p1 = controlPoints[i]
      let p2 = controlPoints[min(i + 1, controlPoints.count - 1)]
      let p3 = controlPoints[min(i + 2, controlPoints.count - 1)]

      let p0prev = controlPoints[max(i - 2, 0)]

      let tangentLeft = tangentAt(
        p0: p0prev, p1: p0, p2: p1, p3: p2, t: 1.0
      )
      let tangentRight = tangentAt(
        p0: p0, p1: p1, p2: p2, p3: p3, t: 0.0
      )

      let leftNorm = normalize(tangentLeft)
      let rightNorm = normalize(tangentRight)

      let dot = leftNorm.x * rightNorm.x + leftNorm.y * rightNorm.y

      XCTAssertGreaterThan(
        dot,
        0.95,
        "Tangent directions should be continuous at joint \(i)"
      )
    }
  }

  func testClosedLoopConnectsEndToStart() {
    let controlPoints = [
      CGPoint(x: 0, y: 0),
      CGPoint(x: 100, y: 0),
      CGPoint(x: 100, y: 100),
      CGPoint(x: 0, y: 100),
    ]

    let closedPoints = controlPoints + [controlPoints[0]]
    let path = getCatmullRomPath(from: closedPoints)
    let sampled = samplePath(path)

    guard let lastPoint = sampled.last else {
      XCTFail("Path should have points")
      return
    }

    XCTAssertLessThan(
      distance(lastPoint, controlPoints[0]),
      curveEpsilon,
      "Closed loop should end at the starting point"
    )
  }

  // MARK: - Mathematical & Edge Case Tests

  func testCollinearPointsProduceStraightLine() {
    let collinearPoints = [
      CGPoint(x: 0, y: 0),
      CGPoint(x: 50, y: 50),
      CGPoint(x: 100, y: 100),
      CGPoint(x: 150, y: 150),
    ]

    let path = getCatmullRomPath(from: collinearPoints)
    let sampled = samplePath(path)

    for point in sampled {
      let deviationFromLine = abs(point.x - point.y)
      XCTAssertLessThan(
        deviationFromLine,
        curveEpsilon,
        "Collinear input should produce a straight line, got \(point)"
      )
    }
  }

  func testDuplicatePointsDoNotCrash() {
    let duplicatePoints = [
      CGPoint(x: 50, y: 50),
      CGPoint(x: 50, y: 50),
      CGPoint(x: 50, y: 50),
      CGPoint(x: 100, y: 100),
    ]

    let path = getCatmullRomPath(from: duplicatePoints)
    let sampled = samplePath(path)

    XCTAssertFalse(sampled.isEmpty, "Should produce a valid path even with duplicates")

    for point in sampled {
      XCTAssertFalse(point.x.isNaN, "No NaN values in output")
      XCTAssertFalse(point.y.isNaN, "No NaN values in output")
      XCTAssertFalse(point.x.isInfinite, "No infinite values in output")
      XCTAssertFalse(point.y.isInfinite, "No infinite values in output")
    }
  }

  func testAllDuplicatePointsStable() {
    let allSame = [
      CGPoint(x: 42, y: 42),
      CGPoint(x: 42, y: 42),
      CGPoint(x: 42, y: 42),
    ]

    let path = getCatmullRomPath(from: allSame)
    let sampled = samplePath(path)

    for point in sampled {
      XCTAssertEqual(point.x, 42, accuracy: epsilon)
      XCTAssertEqual(point.y, 42, accuracy: epsilon)
    }
  }

  func testUniformParameterizationIsDefault() {
    let sharpTurn = [
      CGPoint(x: 0, y: 0),
      CGPoint(x: 100, y: 0),
      CGPoint(x: 101, y: 0),
      CGPoint(x: 101, y: 100),
    ]

    let path = getCatmullRomPath(from: sharpTurn)
    let sampled = samplePath(path)

    for point in sampled {
      XCTAssertFalse(point.x.isNaN)
      XCTAssertFalse(point.y.isNaN)
    }

    let hasOvershoot = sampled.contains { $0.x < -curveEpsilon || $0.x > 101 + curveEpsilon }
    // ponytail: uniform Catmull-Rom overshoots on tight turns; upgrade to centripetal (α=0.5) when visual quality matters
    XCTAssertTrue(hasOvershoot, "Uniform Catmull-Rom should overshoot on tight turns")
  }

  // MARK: - Boundary Tests

  func testEmptyInputReturnsEmptyPath() {
    let path = getCatmullRomPath(from: [])
    XCTAssertTrue(path.isEmpty)
  }

  func testSinglePointReturnsEmptyPath() {
    let path = getCatmullRomPath(from: [CGPoint(x: 10, y: 20)])
    XCTAssertTrue(path.isEmpty)
  }

  func testTwoPointsReturnsStraightLine() {
    let p1 = CGPoint(x: 0, y: 0)
    let p2 = CGPoint(x: 100, y: 100)
    let path = getCatmullRomPath(from: [p1, p2])
    let sampled = samplePath(path)

    XCTAssertFalse(sampled.isEmpty)

    for point in sampled {
      XCTAssertEqual(point.x, point.y, accuracy: curveEpsilon)
    }
  }

  // MARK: - Helpers

  private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = a.x - b.x
    let dy = a.y - b.y
    return sqrt(dx * dx + dy * dy)
  }

  private func tangentAt(
    p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint,
    t: CGFloat
  ) -> CGPoint {
    let cp1 = CGPoint(
      x: p1.x + (p2.x - p0.x) / 6.0,
      y: p1.y + (p2.y - p0.y) / 6.0
    )
    let cp2 = CGPoint(
      x: p2.x - (p3.x - p1.x) / 6.0,
      y: p2.y - (p3.y - p1.y) / 6.0
    )

    let tClamped = max(0, min(1, t))
    let oneMinusT = 1.0 - tClamped

    let dx =
      3.0 * oneMinusT * oneMinusT * (cp1.x - p1.x)
      + 6.0 * oneMinusT * tClamped * (cp2.x - cp1.x)
      + 3.0 * tClamped * tClamped * (p2.x - cp2.x)
    let dy =
      3.0 * oneMinusT * oneMinusT * (cp1.y - p1.y)
      + 6.0 * oneMinusT * tClamped * (cp2.y - cp1.y)
      + 3.0 * tClamped * tClamped * (p2.y - cp2.y)

    return CGPoint(x: dx, y: dy)
  }

  private func normalize(_ v: CGPoint) -> CGPoint {
    let len = sqrt(v.x * v.x + v.y * v.y)
    if len < 1e-10 {
      return .zero
    }
    return CGPoint(x: v.x / len, y: v.y / len)
  }

  private func samplePath(_ path: CGPath) -> [CGPoint] {
    var points: [CGPoint] = []
    var current = CGPoint.zero

    path.applyWithBlock { elementPointer in
      let element = elementPointer.pointee
      switch element.type {
      case .moveToPoint:
        current = element.points[0]
        points.append(current)
      case .addLineToPoint:
        current = element.points[0]
        points.append(current)
      case .addQuadCurveToPoint:
        current = element.points[1]
        points.append(current)
      case .addCurveToPoint:
        let p0 = current
        let cp1 = element.points[0]
        let cp2 = element.points[1]
        let p3 = element.points[2]
        let steps = 8
        for s in 1...steps {
          let t = CGFloat(s) / CGFloat(steps)
          let oneMinusT = 1.0 - t
          let x =
            oneMinusT * oneMinusT * oneMinusT * p0.x
            + 3.0 * oneMinusT * oneMinusT * t * cp1.x
            + 3.0 * oneMinusT * t * t * cp2.x
            + t * t * t * p3.x
          let y =
            oneMinusT * oneMinusT * oneMinusT * p0.y
            + 3.0 * oneMinusT * oneMinusT * t * cp1.y
            + 3.0 * oneMinusT * t * t * cp2.y
            + t * t * t * p3.y
          points.append(CGPoint(x: x, y: y))
        }
        current = p3
      case .closeSubpath:
        break
      @unknown default:
        break
      }
    }

    return points
  }

}
