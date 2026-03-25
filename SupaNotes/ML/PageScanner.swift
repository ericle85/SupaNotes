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

/// Scan strokes through the full pipeline: orient → segment lines → reorder → split → predict.
func scanStrokes(
    _ rawStrokes: [[StrokePoint]],
    model: CTCModel,
    threshold: Float = 0.7
) throws -> PageScanResult {
    guard !rawStrokes.isEmpty else {
        return PageScanResult(lines: [], fullText: "")
    }

    // 1. Orientation correction
    let correction = detectOrientation(rawStrokes)
    let oriented = applyOrientationCorrection(rawStrokes, correction: correction)

    // 2. Segment into lines
    let lines = segmentIntoLines(oriented)

    // 3. Process each line
    var recognizedLines = [RecognizedLine]()

    for (idx, line) in lines.enumerated() {
        // Reorder left-to-right
        let reordered = reorderStrokesLeftToRight(line.strokes)

        // Split if too long
        let segments = splitLineIntoSegments(reordered)

        // Predict each segment and concatenate
        var lineTokens = [TokenDetail]()
        for segment in segments {
            // Zero out timestamps — model doesn't depend on time
            let zeroed = segment.strokes.map { stroke in
                stroke.map { StrokePoint(x: $0.x, y: $0.y, t: 0) }
            }
            let normalized = normalizeStrokes(zeroed)
            let features = extractPointFeatures(normalized)
            let nPoints = features.count / FEATURE_DIM
            guard nPoints > 0 else { continue }

            let result = try model.predict(features: features, seqLen: nPoints, threshold: threshold)
            lineTokens.append(contentsOf: result.tokens)
        }

        let text = lineTokens.map(\.token).joined()
        let avgConf = lineTokens.isEmpty ? 0 : lineTokens.map(\.confidence).reduce(0, +) / Float(lineTokens.count)

        recognizedLines.append(RecognizedLine(
            lineIndex: idx,
            text: text,
            tokens: lineTokens,
            boundingBox: line.boundingBox,
            confidence: avgConf
        ))
    }

    let fullText = recognizedLines.map(\.text).joined(separator: "\n")
    return PageScanResult(lines: recognizedLines, fullText: fullText)
}
