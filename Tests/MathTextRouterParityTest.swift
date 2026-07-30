import Foundation
import Testing

@testable import SupaNotes

struct ParityEntry: Decodable {
    let fixture: String
    let group_index: Int
    let content: String
    let confidence: Float
    let token_confidences: [Float]
    let route_heuristic: String
    let route_ml: String
    let features_numeric: [Double]
    let features_layout: [Double]
    let strokes: [[StrokePoint]]

    struct StrokePoint: Decodable {
        let x: Float
        let y: Float
        let t: Float
    }
}

@Test func routerParityWithPython() throws {
    let url = Bundle(for: BundleToken.self).url(forResource: "routing_parity", withExtension: "json")
        ?? Bundle.main.url(forResource: "routing_parity", withExtension: "json")
    guard let url else {
        let testDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fallback = testDir.appendingPathComponent("routing_parity.json")
        guard FileManager.default.fileExists(atPath: fallback.path) else {
            Issue.record("routing_parity.json not found")
            return
        }
        try runParity(url: fallback)
        return
    }
    try runParity(url: url)
}

private func runParity(url: URL) throws {
    let data = try Data(contentsOf: url)
    let entries = try JSONDecoder().decode([ParityEntry].self, from: data)
    #expect(entries.count > 0)

    for entry in entries {
        let strokes: [[CTCPoint]] = entry.strokes.map { stroke in
            stroke.map { CTCPoint(x: $0.x, y: $0.y, t: $0.t) }
        }

        let swiftNumeric = routerFeatures(content: entry.content, tokenConfidences: entry.token_confidences)
        for (i, (swift, python)) in zip(swiftNumeric, entry.features_numeric).enumerated() {
            #expect(
                abs(swift - python) < 1e-4,
                "numeric feature \(i) mismatch for \(entry.fixture) group \(entry.group_index): swift=\(swift) python=\(python)"
            )
        }

        let swiftLayout = strokeLayoutFeatures(strokes)
        for (i, (swift, python)) in zip(swiftLayout, entry.features_layout).enumerated() {
            #expect(
                abs(swift - python) < 1e-4,
                "layout feature \(i) mismatch for \(entry.fixture) group \(entry.group_index): swift=\(swift) python=\(python)"
            )
        }

        let swiftKind = routeGroup(
            content: entry.content,
            tokenConfidences: entry.token_confidences,
            strokes: strokes
        )
        let expectedKind = entry.route_ml == "math" ? RecognizedKind.math : RecognizedKind.text
        #expect(
            swiftKind == expectedKind,
            "routing mismatch for \(entry.fixture) group \(entry.group_index): content='\(entry.content)' swift=\(swiftKind) python=\(entry.route_ml)"
        )
    }
}

private final class BundleToken {}
