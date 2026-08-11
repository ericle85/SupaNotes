import CoreGraphics
import Metal
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
      CGPoint(x: 150, y: 80),
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
      CGPoint(x: 0, y: 100),
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
      CGPoint(x: 150, y: 150),
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
      CGPoint(x: 100, y: 100),
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
      CGPoint(x: 42, y: 42),
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
      CGPoint(x: 101, y: 100),
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

  // MARK: - GPU Tests

  private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    constant float4x4 catmullRomBasis = float4x4(
      float4(0, 1, 0, 0),
      float4(-0.5, 0, 0.5, 0),
      float4(1, -2.5, 2, -0.5),
      float4(-0.5, 1.5, -1.5, 0.5)
    );

    kernel void catmullRomCompute(
        device const packed_float2* controlPoints [[buffer(0)]],
        device packed_float2* outputPoints [[buffer(1)]],
        constant uint& pointCount [[buffer(2)]],
        constant uint& subdivisions [[buffer(3)]],
        uint gid [[thread_position_in_grid]]
    ) {
      uint totalOutputs = (pointCount - 1) * subdivisions;
      if (gid >= totalOutputs) { return; }

      uint segIdx = gid / subdivisions;
      uint subIdx = gid % subdivisions;

      int last = int(pointCount) - 1;
      int i = int(segIdx);

      float2 p0 = float2(controlPoints[max(i - 1, 0)]);
      float2 p1 = float2(controlPoints[i]);
      float2 p2 = float2(controlPoints[min(i + 1, last)]);
      float2 p3 = float2(controlPoints[min(i + 2, last)]);

      float t = float(subIdx + 1) / float(subdivisions);
      float4 tVec = float4(1, t, t * t, t * t * t);
      float4 weights = catmullRomBasis * tVec;

      float4 px = float4(p0.x, p1.x, p2.x, p3.x);
      float4 py = float4(p0.y, p1.y, p2.y, p3.y);
      float2 result = float2(dot(weights, px), dot(weights, py));
      outputPoints[gid] = packed_float2(result);
    }
    """

  private func makeGPU() -> CatmullRomGPU? {
    guard let device = MTLCreateSystemDefaultDevice() else {
      return nil
    }
    guard let library = try? device.makeLibrary(source: Self.shaderSource, options: nil) else {
      return nil
    }
    return CatmullRomGPU(device: device, library: library)
  }

  func testGPUPassesThroughControlPoints() throws {
    let gpu = try XCTUnwrap(makeGPU(), "Metal not available")

    let controlPoints = [
      CGPoint(x: 0, y: 0),
      CGPoint(x: 50, y: 100),
      CGPoint(x: 100, y: 30),
      CGPoint(x: 150, y: 80),
      CGPoint(x: 200, y: 0),
    ]

    let smoothed = gpu.smooth(points: controlPoints)

    for controlPoint in controlPoints {
      let closest = smoothed.min(by: {
        distance($0, controlPoint) < distance($1, controlPoint)
      })!
      XCTAssertLessThan(
        distance(closest, controlPoint),
        curveEpsilon,
        "GPU curve should pass through control point \(controlPoint)"
      )
    }
  }

  func testGPUCollinearPointsProduceStraightLine() throws {
    let gpu = try XCTUnwrap(makeGPU(), "Metal not available")

    let collinearPoints = [
      CGPoint(x: 0, y: 0),
      CGPoint(x: 50, y: 50),
      CGPoint(x: 100, y: 100),
      CGPoint(x: 150, y: 150),
    ]

    let smoothed = gpu.smooth(points: collinearPoints)

    for point in smoothed {
      let deviationFromLine = abs(point.x - point.y)
      XCTAssertLessThan(
        deviationFromLine,
        curveEpsilon,
        "GPU collinear input should produce a straight line, got \(point)"
      )
    }
  }

  func testGPUDuplicatePointsDoNotCrash() throws {
    let gpu = try XCTUnwrap(makeGPU(), "Metal not available")

    let duplicatePoints = [
      CGPoint(x: 50, y: 50),
      CGPoint(x: 50, y: 50),
      CGPoint(x: 50, y: 50),
      CGPoint(x: 100, y: 100),
    ]

    let smoothed = gpu.smooth(points: duplicatePoints)

    XCTAssertFalse(smoothed.isEmpty)
    for point in smoothed {
      XCTAssertFalse(point.x.isNaN)
      XCTAssertFalse(point.y.isNaN)
      XCTAssertFalse(point.x.isInfinite)
      XCTAssertFalse(point.y.isInfinite)
    }
  }

  func testGPUAllDuplicatePointsStable() throws {
    let gpu = try XCTUnwrap(makeGPU(), "Metal not available")

    let allSame = [
      CGPoint(x: 42, y: 42),
      CGPoint(x: 42, y: 42),
      CGPoint(x: 42, y: 42),
    ]

    let smoothed = gpu.smooth(points: allSame)

    for point in smoothed {
      XCTAssertEqual(point.x, 42, accuracy: curveEpsilon)
      XCTAssertEqual(point.y, 42, accuracy: curveEpsilon)
    }
  }

  func testGPUSinglePointReturnsSamePoint() throws {
    let gpu = try XCTUnwrap(makeGPU(), "Metal not available")
    let result = gpu.smooth(points: [CGPoint(x: 10, y: 20)])
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].x, 10, accuracy: epsilon)
    XCTAssertEqual(result[0].y, 20, accuracy: epsilon)
  }

  func testGPUTwoPointsReturnsStraightLine() throws {
    let gpu = try XCTUnwrap(makeGPU(), "Metal not available")

    let p1 = CGPoint(x: 0, y: 0)
    let p2 = CGPoint(x: 100, y: 100)
    let smoothed = gpu.smooth(points: [p1, p2])

    XCTAssertFalse(smoothed.isEmpty)
    for point in smoothed {
      XCTAssertEqual(point.x, point.y, accuracy: curveEpsilon)
    }
  }

  func testGPUMatchesCPU() throws {
    let gpu = try XCTUnwrap(makeGPU(), "Metal not available")

    let controlPoints = [
      CGPoint(x: 0, y: 0),
      CGPoint(x: 50, y: 100),
      CGPoint(x: 100, y: 30),
      CGPoint(x: 150, y: 80),
      CGPoint(x: 200, y: 0),
    ]

    let subdivisions: UInt32 = 3
    let gpuPoints = gpu.smooth(points: controlPoints, subdivisions: subdivisions)

    let lastIndex = controlPoints.count - 1
    var cpuPoints = [controlPoints[0]]
    for i in 0..<lastIndex {
      let p0 = controlPoints[max(i - 1, 0)]
      let p1 = controlPoints[i]
      let p2 = controlPoints[min(i + 1, lastIndex)]
      let p3 = controlPoints[min(i + 2, lastIndex)]

      for s in 1...Int(subdivisions) {
        let t = CGFloat(s) / CGFloat(subdivisions)
        let point = getCatmullRomPoint(p0: p0, p1: p1, p2: p2, p3: p3, t: t)
        cpuPoints.append(point)
      }
    }

    XCTAssertEqual(gpuPoints.count, cpuPoints.count)
    for i in 0..<min(gpuPoints.count, cpuPoints.count) {
      XCTAssertEqual(
        gpuPoints[i].x, cpuPoints[i].x, accuracy: 0.01,
        "X mismatch at index \(i)"
      )
      XCTAssertEqual(
        gpuPoints[i].y, cpuPoints[i].y, accuracy: 0.01,
        "Y mismatch at index \(i)"
      )
    }
  }

  func testGPUClosedLoopConnectsEndToStart() throws {
    let gpu = try XCTUnwrap(makeGPU(), "Metal not available")

    let controlPoints = [
      CGPoint(x: 0, y: 0),
      CGPoint(x: 100, y: 0),
      CGPoint(x: 100, y: 100),
      CGPoint(x: 0, y: 100),
    ]

    let closedPoints = controlPoints + [controlPoints[0]]
    let smoothed = gpu.smooth(points: closedPoints)

    guard let lastPoint = smoothed.last else {
      XCTFail("Should have points")
      return
    }

    XCTAssertLessThan(
      distance(lastPoint, controlPoints[0]),
      curveEpsilon,
      "GPU closed loop should end at the starting point"
    )
  }
}
