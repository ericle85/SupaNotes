import XCTest
@testable import SupaNotesSwift

final class StrokePreprocessingTests: XCTestCase {

    private let tolerance: Float = 1e-4

    private func arcLength(_ stroke: [StrokePoint]) -> Float {
        var total: Float = 0
        for i in 1..<stroke.count {
            let dx = stroke[i].x - stroke[i - 1].x
            let dy = stroke[i].y - stroke[i - 1].y
            total += sqrt(dx * dx + dy * dy)
        }
        return total
    }

    func testResamplePreservesEndpoints() {
        let stroke = [
            StrokePoint(x: 0, y: 0, t: 0),
            StrokePoint(x: 10, y: 0, t: 0.5),
            StrokePoint(x: 10, y: 10, t: 1),
        ]

        let resampled = resampleStroke(stroke)

        XCTAssertEqual(resampled.first!.x, stroke.first!.x, accuracy: tolerance)
        XCTAssertEqual(resampled.first!.y, stroke.first!.y, accuracy: tolerance)
        XCTAssertEqual(resampled.last!.x, stroke.last!.x, accuracy: tolerance)
        XCTAssertEqual(resampled.last!.y, stroke.last!.y, accuracy: tolerance)
    }

    func testResamplePreservesArcLength() {
        let stroke = [
            StrokePoint(x: 0, y: 0, t: 0),
            StrokePoint(x: 3, y: 4, t: 0.5),
            StrokePoint(x: 6, y: 0, t: 1),
        ]

        let originalLength = arcLength(stroke)
        let resampledLength = arcLength(resampleStroke(stroke))

        XCTAssertEqual(resampledLength, originalLength, accuracy: tolerance)
    }

    func testResampleTwiceMatchesResampleOnce() {
        let count = 10
        let stroke = (0..<count).map { i in
            StrokePoint(
                x: Float(i) * RESAMPLE_STEP,
                y: 0,
                t: Float(i) * 0.1
            )
        }

        let resampled = resampleStroke(stroke)
        let resampledTwice = resampleStroke(resampled)

        XCTAssertEqual(resampled.count, resampledTwice.count)
        for i in resampled.indices {
            XCTAssertEqual(resampled[i].x, resampledTwice[i].x, accuracy: tolerance)
            XCTAssertEqual(resampled[i].y, resampledTwice[i].y, accuracy: tolerance)
        }
    }

    func testResampleSinglePointReturnsSame() {
        let stroke = [StrokePoint(x: 5, y: 5, t: 0)]
        let resampled = resampleStroke(stroke)

        XCTAssertEqual(resampled.count, 1)
        XCTAssertEqual(resampled[0].x, 5)
        XCTAssertEqual(resampled[0].y, 5)
    }

    func testResampleEmptyReturnsEmpty() {
        let resampled = resampleStroke([])
        XCTAssertTrue(resampled.isEmpty)
    }

    func testResampleMonotonicTime() {
        let stroke = [
            StrokePoint(x: 0, y: 0, t: 0),
            StrokePoint(x: 5, y: 5, t: 0.5),
            StrokePoint(x: 10, y: 0, t: 1),
        ]

        let resampled = resampleStroke(stroke)

        for i in 1..<resampled.count {
            XCTAssertGreaterThanOrEqual(resampled[i].t, resampled[i - 1].t)
        }
    }

    func testCumulativeArcLengthMonotonic() {
        let stroke = [
            StrokePoint(x: 0, y: 0, t: 0),
            StrokePoint(x: 3, y: 4, t: 0.5),
            StrokePoint(x: 6, y: 0, t: 1),
        ]

        let cumLen = cumulativeArcLength(stroke)

        XCTAssertEqual(cumLen[0], 0)
        for i in 1..<cumLen.count {
            XCTAssertGreaterThan(cumLen[i], cumLen[i - 1])
        }
    }

    func testCumulativeArcLengthCorrectness() {
        let stroke = [
            StrokePoint(x: 0, y: 0, t: 0),
            StrokePoint(x: 3, y: 4, t: 0.5),
        ]

        let cumLen = cumulativeArcLength(stroke)

        XCTAssertEqual(cumLen[0], 0)
        XCTAssertEqual(cumLen[1], 5, accuracy: tolerance)
    }

    func testResampleZeroLengthStroke() {
        let stroke = [
            StrokePoint(x: 5, y: 5, t: 0),
            StrokePoint(x: 5, y: 5, t: 1),
        ]

        let resampled = resampleStroke(stroke)

        XCTAssertEqual(resampled.count, 1)
        XCTAssertEqual(resampled[0].x, 5)
        XCTAssertEqual(resampled[0].y, 5)
    }
}
