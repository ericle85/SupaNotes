import Foundation
import CoreGraphics

struct RecognizedLine {
    let lineIndex: Int
    let text: String
    let tokens: [TokenDetail]
    let boundingBox: CGRect
    let confidence: Float // average token confidence
}

struct PageScanResult {
    let lines: [RecognizedLine]
    let fullText: String
}

/// Scan strokes: normalize all together → extract features → predict.
func scanStrokes(
    _ rawStrokes: [[StrokePoint]],
    model: CTCModel,
    threshold: Float = 0.53
) throws -> PageScanResult {
    guard !rawStrokes.isEmpty else {
        return PageScanResult(lines: [], fullText: "")
    }

    let normalized = normalizeStrokes(rawStrokes)
    let features = extractPointFeatures(normalized)
    let nPoints = features.count / FEATURE_DIM
    guard nPoints >= 2 else {
        return PageScanResult(lines: [], fullText: "")
    }

    let result = try model.predict(features: features, seqLen: nPoints, threshold: threshold)
    let text = result.tokens.map(\.token).joined()
    let avgConf = result.tokens.isEmpty ? 0 : result.tokens.map(\.confidence).reduce(0, +) / Float(result.tokens.count)

    // Compute bounding box from all strokes
    var minX: Float = .greatestFiniteMagnitude
    var minY: Float = .greatestFiniteMagnitude
    var maxX: Float = -.greatestFiniteMagnitude
    var maxY: Float = -.greatestFiniteMagnitude
    for stroke in rawStrokes {
        for p in stroke {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
    }
    let bbox = CGRect(x: CGFloat(minX), y: CGFloat(minY),
                      width: CGFloat(maxX - minX), height: CGFloat(maxY - minY))

    let line = RecognizedLine(
        lineIndex: 0, text: text, tokens: result.tokens,
        boundingBox: bbox, confidence: avgConf
    )
    return PageScanResult(lines: [line], fullText: text)
}
