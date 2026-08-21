import XCTest
@testable import SupaNotesSwift

final class StrokeNormalizationTests: XCTestCase {

    private let tolerance: Float = 1e-5

    private func denormalizePoint(_ point: StrokePoint, bbox: StrokeBoundingBox) -> StrokePoint {
        StrokePoint(
            x: point.x * bbox.uniformScale + bbox.centerX,
            y: point.y * bbox.uniformScale + bbox.centerY,
            t: point.t * bbox.spanT + bbox.minT
        )
    }

    func testNormalizeThenDenormalizeSinglePoint() {
        let original = StrokePoint(x: 150, y: 200, t: 0.5)
        let bbox = StrokeBoundingBox(
            minX: 100, maxX: 300,
            minY: 50, maxY: 250,
            minT: 0, maxT: 1
        )

        let normalized = normalizePoint(original, bbox: bbox)
        let restored = denormalizePoint(normalized, bbox: bbox)

        XCTAssertEqual(restored.x, original.x, accuracy: tolerance)
        XCTAssertEqual(restored.y, original.y, accuracy: tolerance)
        XCTAssertEqual(restored.t, original.t, accuracy: tolerance)
    }

    func testNormalizeThenDenormalizeMultipleStrokes() {
        let strokes: [[StrokePoint]] = [
            [
                StrokePoint(x: 10, y: 20, t: 0),
                StrokePoint(x: 50, y: 80, t: 0.5),
            ],
            [
                StrokePoint(x: 30, y: 40, t: 1.0),
                StrokePoint(x: 90, y: 100, t: 1.5),
            ],
        ]

        let allPoints = strokes.flatMap { $0 }
        let bbox = strokeBoundingBox(allPoints)
        let normalized = normalizeStrokes(strokes)

        for (si, stroke) in normalized.enumerated() {
            for (pi, point) in stroke.enumerated() {
                let restored = denormalizePoint(point, bbox: bbox)
                let original = strokes[si][pi]
                XCTAssertEqual(restored.x, original.x, accuracy: tolerance)
                XCTAssertEqual(restored.y, original.y, accuracy: tolerance)
                XCTAssertEqual(restored.t, original.t, accuracy: tolerance)
            }
        }
    }

    func testNormalizeEmptyStrokesReturnsEmpty() {
        let result = normalizeStrokes([])
        XCTAssertTrue(result.isEmpty)
    }

    func testNormalizedValuesAreCentered() {
        let strokes: [[StrokePoint]] = [
            [
                StrokePoint(x: 0, y: 0, t: 0),
                StrokePoint(x: 100, y: 100, t: 1),
            ],
        ]

        let normalized = normalizeStrokes(strokes)
        let xs = normalized.flatMap { $0.map(\.x) }
        let ys = normalized.flatMap { $0.map(\.y) }

        let meanX = xs.reduce(0, +) / Float(xs.count)
        let meanY = ys.reduce(0, +) / Float(ys.count)

        XCTAssertEqual(meanX, 0, accuracy: tolerance)
        XCTAssertEqual(meanY, 0, accuracy: tolerance)
    }

    func testNormalizedTimeStartsAtZeroEndsAtOne() {
        let strokes: [[StrokePoint]] = [
            [
                StrokePoint(x: 0, y: 0, t: 5),
                StrokePoint(x: 10, y: 10, t: 15),
            ],
        ]

        let normalized = normalizeStrokes(strokes)
        let ts = normalized.flatMap { $0.map(\.t) }

        XCTAssertEqual(ts.first!, 0, accuracy: tolerance)
        XCTAssertEqual(ts.last!, 1, accuracy: tolerance)
    }

    func testBoundingBoxSpanClampsToEpsilon() {
        let point = StrokePoint(x: 5, y: 5, t: 0)
        let bbox = strokeBoundingBox([point])

        XCTAssertGreaterThan(bbox.spanX, 0)
        XCTAssertGreaterThan(bbox.spanY, 0)
        XCTAssertGreaterThan(bbox.spanT, 0)
    }

    func testResampleToFixedLengthRoundTrip() {
        let xs: [Float] = [0, 1, 2, 3, 4]
        let ys: [Float] = [0, 2, 4, 6, 8]

        let resampled = resampleToFixedLength(xs, ys, count: 5)

        for i in 0..<5 {
            XCTAssertEqual(resampled.xs[i], xs[i], accuracy: tolerance)
            XCTAssertEqual(resampled.ys[i], ys[i], accuracy: tolerance)
        }
    }

    func testResampleToFixedLengthEmptyInput() {
        let result = resampleToFixedLength([], [], count: 3)

        XCTAssertEqual(result.xs, [0, 0, 0])
        XCTAssertEqual(result.ys, [0, 0, 0])
    }

    func testResampleToFixedLengthSinglePoint() {
        let result = resampleToFixedLength([7], [3], count: 4)

        for i in 0..<4 {
            XCTAssertEqual(result.xs[i], 7)
            XCTAssertEqual(result.ys[i], 3)
        }
    }
}
