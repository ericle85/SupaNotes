import XCTest
@testable import SupaNotesSwift

final class StrokeFeaturesTests: XCTestCase {

    private let tolerance: Float = 1e-5

    func testFeatureDimensionIsMultipleOfSix() {
        let strokes: [[StrokePoint]] = [
            [
                StrokePoint(x: 0, y: 0, t: 0),
                StrokePoint(x: 1, y: 1, t: 0.5),
            ],
        ]

        let features = extractPointFeatures(strokes)

        XCTAssertEqual(features.count % FEATURE_DIM, 0)
    }

    func testFeatureMaxLength() {
        var longStroke = [StrokePoint]()
        for i in 0..<5000 {
            longStroke.append(StrokePoint(x: Float(i) * 0.001, y: 0, t: Float(i)))
        }

        let features = extractPointFeatures([longStroke])

        XCTAssertLessThanOrEqual(features.count, MAX_SEQ_LEN * FEATURE_DIM)
    }

    func testFirstPointDeltasAreZero() {
        let strokes: [[StrokePoint]] = [
            [
                StrokePoint(x: 0, y: 0, t: 0),
                StrokePoint(x: 1, y: 1, t: 0.5),
            ],
        ]

        let features = extractPointFeatures(strokes)

        let dx = features[2]
        let dy = features[3]
        let dt = features[4]

        XCTAssertEqual(dx, 0, accuracy: tolerance)
        XCTAssertEqual(dy, 0, accuracy: tolerance)
        XCTAssertEqual(dt, 0, accuracy: tolerance)
    }

    func testPenStateZeroForFirstStroke() {
        let strokes: [[StrokePoint]] = [
            [
                StrokePoint(x: 0, y: 0, t: 0),
                StrokePoint(x: 1, y: 1, t: 0.5),
            ],
        ]

        let features = extractPointFeatures(strokes)

        let penState = features[5]
        XCTAssertEqual(penState, 0)
    }

    func testPenStateOneAtSecondStrokeStart() {
        let strokes: [[StrokePoint]] = [
            [
                StrokePoint(x: 0, y: 0, t: 0),
                StrokePoint(x: 1, y: 0, t: 0.5),
            ],
            [
                StrokePoint(x: 2, y: 0, t: 1),
                StrokePoint(x: 3, y: 0, t: 1.5),
            ],
        ]

        let features = extractPointFeatures(strokes)

        let stroke1Resampled = resampleStroke(strokes[0])
        let secondStrokeStartIdx = stroke1Resampled.count * FEATURE_DIM
        let penState = features[secondStrokeStartIdx + 5]

        XCTAssertEqual(penState, 1)
    }

    func testEmptyStrokesReturnsEmptyFeatures() {
        let features = extractPointFeatures([])
        XCTAssertTrue(features.isEmpty)
    }

    func testSameInputProducesSameOutput() {
        let strokes: [[StrokePoint]] = [
            [
                StrokePoint(x: 10, y: 20, t: 0),
                StrokePoint(x: 30, y: 40, t: 1),
            ],
        ]

        let first = extractPointFeatures(strokes)
        let second = extractPointFeatures(strokes)

        XCTAssertEqual(first, second)
    }
}
