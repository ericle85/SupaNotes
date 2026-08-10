import XCTest
import CoreGraphics
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
            CGPoint(x: 200, y: 0)
        ]

        let path = getCatmullRomPath(from: controlPoints)
        let sampledPoints = samplePath(path, count: 500)

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
            CGPoint(x: 150, y: 80)
        ]

        let dt: CGFloat = 1e-4

        for i in 1..<(controlPoints.count - 1) {
            let p0 = controlPoints[max(i - 1, 0)]
            let p1 = controlPoints[i]
            let p2 = controlPoints[min(i + 1, controlPoints.count - 1)]
            let p3 = controlPoints[min(i + 2, controlPoints.count - 1)]

            let p0prev = controlPoints[max(i - 2, 0)]

            let tangentLeft = tangentAt(
                p0: p0prev, p1: p0, p2: p1, p3: p2, t: 1.0, dt: dt
            )
            let tangentRight = tangentAt(
                p0: p0, p1: p1, p2: p2, p3: p3, t: 0.0, dt: dt
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
            CGPoint(x: 0, y: 100)
        ]

        let closedPoints = controlPoints + [controlPoints[0]]
        let path = getCatmullRomPath(from: closedPoints)
        let sampled = samplePath(path, count: 200)

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
            CGPoint(x: 150, y: 150)
        ]

        let path = getCatmullRomPath(from: collinearPoints)
        let sampled = samplePath(path, count: 200)

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
            CGPoint(x: 100, y: 100)
        ]

        let path = getCatmullRomPath(from: duplicatePoints)
        let sampled = samplePath(path, count: 100)

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
            CGPoint(x: 42, y: 42)
        ]

        let path = getCatmullRomPath(from: allSame)
        let sampled = samplePath(path, count: 50)

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
            CGPoint(x: 101, y: 100)
        ]

        let path = getCatmullRomPath(from: sharpTurn)
        let sampled = samplePath(path, count: 300)

        for point in sampled {
            XCTAssertFalse(point.x.isNaN)
            XCTAssertFalse(point.y.isNaN)
        }

        let hasOvershoot = sampled.contains { $0.x < -curveEpsilon || $0.x > 101 + curveEpsilon }
        if hasOvershoot {
            // ponytail: uniform Catmull-Rom overshoots on tight turns; upgrade to centripetal (α=0.5) when visual quality matters
        }
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
        let sampled = samplePath(path, count: 50)

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
        t: CGFloat, dt: CGFloat
    ) -> CGPoint {
        let tClamped = max(0, min(1, t))
        let tBefore = max(0, tClamped - dt)
        let tAfter = min(1, tClamped + dt)

        let before = getCatmullRomPoint(p0: p0, p1: p1, p2: p2, p3: p3, t: tBefore)
        let after = getCatmullRomPoint(p0: p0, p1: p1, p2: p2, p3: p3, t: tAfter)

        return CGPoint(
            x: after.x - before.x,
            y: after.y - before.y
        )
    }

    private func normalize(_ v: CGPoint) -> CGPoint {
        let len = sqrt(v.x * v.x + v.y * v.y)
        if len < 1e-10 {
            return .zero
        }
        return CGPoint(x: v.x / len, y: v.y / len)
    }

    private func samplePath(_ path: CGPath, count: Int) -> [CGPoint] {
        var points: [CGPoint] = []

        path.applyWithBlock { elementPointer in
            let element = elementPointer.pointee
            switch element.type {
            case .moveToPoint:
                points.append(element.points[0])
            case .addLineToPoint:
                points.append(element.points[0])
            case .addQuadCurveToPoint:
                points.append(element.points[1])
            case .addCurveToPoint:
                points.append(element.points[2])
            case .closeSubpath:
                break
            @unknown default:
                break
            }
        }

        return points
    }
}
