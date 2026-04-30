import Testing
import Foundation
import SwiftUI
import CoreGraphics
@testable import SupaNotes

// Tests for the encoder/decoder that turns drawings into saveable bytes and back.
@Suite struct CodecTests {

    // Helper to build a stroke with known points.
    private func makeStroke(
        points: [(CGFloat, CGFloat, CGFloat?)],
        width: CGFloat = 3
    ) -> Stroke {
        Stroke(
            id: UUID(),
            tool: .pen,
            color: CodableColor(color: .black),
            width: width,
            points: points.map { StrokePoint(CGPoint(x: $0.0, y: $0.1), pressure: $0.2) }
        )
    }

    // 2.1 — Encode then decode gets the same drawing back.
    @Test func roundTrip_preservesStrokes() {
        var page = DrawingPage() // init with empty page
        page.strokes = [
            makeStroke(points: [(10, 20, 0.5), (30, 40, 0.8)]), // points are (x, y, pressure)
            makeStroke(points: [(100, 200, nil), (300, 400, nil)]),
        ]

        let data = DrawingCodec.encode(currentPage: page)
        let decoded = DrawingCodec.decode(data: data)

        #expect(decoded.strokes.count == 2)
        #expect(decoded.strokes[0].points.count == 2)
        #expect(decoded.strokes[1].points.count == 2)
        // Check first stroke's first point.
        #expect(decoded.strokes[0].points[0].pointX == 10)
        #expect(decoded.strokes[0].points[0].pointY == 20)
    }

    // 2.2 — Empty data gives a blank page.
    @Test func decode_emptyData_returnsEmptyDocument() {
        let page = DrawingCodec.decode(data: Data())
        #expect(page.strokes.isEmpty)
    }

    // 2.3 — Garbage data gives a blank page, not a crash.
    @Test func decode_garbageData_returnsEmptyDocument() {
        let garbage = "this is not json at all".data(using: .utf8)!
        let page = DrawingCodec.decode(data: garbage)
        #expect(page.strokes.isEmpty)
    }

    // 2.4 — Pressure values survive the round trip (high, low, nil).
    @Test func roundTrip_preservesPressure() {
        var page = DrawingPage()
        page.strokes = [
            makeStroke(points: [(0, 0, 0.9), (10, 10, 0.1), (20, 20, nil)])
        ]

        let data = DrawingCodec.encode(currentPage: page)
        let decoded = DrawingCodec.decode(data: data)

        let pts = decoded.strokes[0].points
        #expect(pts[0].pressure == 0.9)
        #expect(pts[1].pressure == 0.1)
        #expect(pts[2].pressure == nil)
    }
}
