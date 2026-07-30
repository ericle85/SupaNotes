import Combine
import Foundation
import UIKit

// MARK: - Recognized Block

enum RecognizedKind: String {
    case math
    case text
    case ink
}

struct RecognizedBlock: Identifiable, Equatable {
    let id: String
    let kind: RecognizedKind
    let content: String
    let confidence: Float
    let bbox: CGRect
    let strokeIndices: [Int]
    let recognizedAt: TimeInterval
    let tokens: [CTCTokenDetail]
}

// MARK: - Stroke Grouping

struct StrokeGroup {
    var strokeIndices: [Int]
    var bbox: CGRect
    var centerY: CGFloat
    var height: CGFloat
    var lastT: TimeInterval
}

private let SPLIT_GAP_PX: CGFloat = 40.0
private let LINE_MERGE_MIN_THRESHOLD: CGFloat = 34.0
private let LINE_MERGE_HEIGHT_FACTOR: CGFloat = 1.15

private func strokeBBox(_ stroke: Stroke) -> CGRect? {
    guard let first = stroke.points.first else { return nil }
    return stroke.points.dropFirst().reduce(CGRect(origin: first.location, size: .zero)) { box, point in
        box.union(CGRect(origin: point.location, size: .zero))
    }
}

private func strokeEndTime(_ stroke: Stroke) -> TimeInterval {
    stroke.points.last?.timestamp ?? 0
}

private func buildGroup(strokeIndices: [Int], strokes: [Stroke]) -> StrokeGroup {
    var unionBox: CGRect? = nil
    var lastT: TimeInterval = 0

    for idx in strokeIndices {
        if let bbox = strokeBBox(strokes[idx]) {
            if let existing = unionBox {
                unionBox = existing.union(bbox)
            } else {
                unionBox = bbox
            }
        }
        lastT = max(lastT, strokeEndTime(strokes[idx]))
    }

    let bbox = unionBox ?? .zero
    return StrokeGroup(
        strokeIndices: strokeIndices,
        bbox: bbox,
        centerY: bbox.midY,
        height: max(1.0, bbox.height),
        lastT: lastT
    )
}

private func sortByTimeOrder(_ indices: [Int], strokes: [Stroke]) -> [Int] {
    indices.sorted { a, b in
        let tA = strokes[a].points.first?.timestamp ?? 0
        let tB = strokes[b].points.first?.timestamp ?? 0
        return tA < tB
    }
}

private func verticalLines(strokeIndices: [Int], strokes: [Stroke]) -> [StrokeGroup] {
    let sorted = strokeIndices.sorted { a, b in
        let bboxA = strokeBBox(strokes[a]) ?? .zero
        let bboxB = strokeBBox(strokes[b]) ?? .zero
        return bboxA.minY < bboxB.minY
    }

    var lines: [StrokeGroup] = []

    for idx in sorted {
        guard let bbox = strokeBBox(strokes[idx]) else { continue }

        let centerY = bbox.midY
        let height = max(1.0, bbox.height)
        var bestLineIndex: Int? = nil
        var bestDistance: CGFloat = .greatestFiniteMagnitude

        for (lineIdx, line) in lines.enumerated() {
            let threshold = max(LINE_MERGE_MIN_THRESHOLD, max(line.height, height) * LINE_MERGE_HEIGHT_FACTOR)
            let distance = abs(centerY - line.centerY)
            if distance < threshold, distance < bestDistance {
                bestLineIndex = lineIdx
                bestDistance = distance
            }
        }

        if let lineIdx = bestLineIndex {
            lines[lineIdx].strokeIndices.append(idx)
            lines[lineIdx].bbox = lines[lineIdx].bbox.union(bbox)
            lines[lineIdx].centerY = lines[lineIdx].bbox.midY
            lines[lineIdx].height = max(1.0, lines[lineIdx].bbox.height)
            lines[lineIdx].lastT = max(lines[lineIdx].lastT, strokeEndTime(strokes[idx]))
        } else {
            lines.append(StrokeGroup(
                strokeIndices: [idx],
                bbox: bbox,
                centerY: centerY,
                height: max(1.0, bbox.height),
                lastT: strokeEndTime(strokes[idx])
            ))
        }
    }

    return lines
}

private func splitLineIntoChunks(_ line: StrokeGroup, strokes: [Stroke]) -> [StrokeGroup] {
    let validIndices = line.strokeIndices.filter { strokeBBox(strokes[$0]) != nil }
    if validIndices.count < 2 {
        let ordered = sortByTimeOrder(line.strokeIndices, strokes: strokes)
        return [buildGroup(strokeIndices: ordered, strokes: strokes)]
    }

    let sorted = validIndices.sorted { a, b in
        strokeBBox(strokes[a])!.minX < strokeBBox(strokes[b])!.minX
    }

    var chunks: [[Int]] = [[sorted[0]]]
    var runningRight = strokeBBox(strokes[sorted[0]])!.maxX

    for idx in sorted.dropFirst() {
        let bbox = strokeBBox(strokes[idx])!
        if bbox.minX - runningRight > SPLIT_GAP_PX {
            chunks.append([idx])
        } else {
            chunks[chunks.count - 1].append(idx)
        }
        runningRight = max(runningRight, bbox.maxX)
    }

    if chunks.count == 1 {
        let ordered = sortByTimeOrder(line.strokeIndices, strokes: strokes)
        return [buildGroup(strokeIndices: ordered, strokes: strokes)]
    }

    return chunks.map { chunkIndices in
        let ordered = sortByTimeOrder(chunkIndices, strokes: strokes)
        return buildGroup(strokeIndices: ordered, strokes: strokes)
    }
}

func groupStrokes(_ strokes: [Stroke]) -> [StrokeGroup] {
    let allIndices = Array(0 ..< strokes.count)
    var chunks: [StrokeGroup] = []
    for line in verticalLines(strokeIndices: allIndices, strokes: strokes) {
        chunks.append(contentsOf: splitLineIntoChunks(line, strokes: strokes))
    }
    return chunks.sorted { a, b in
        if a.bbox.minY != b.bbox.minY { return a.bbox.minY < b.bbox.minY }
        return a.bbox.minX < b.bbox.minX
    }
}

// MARK: - Math/Text Routing

private let INK_MINIMUM_SPAN_PX: CGFloat = 6.0
private let INK_ASPECT_RATIO_MIN: CGFloat = 0.15
private let INK_ASPECT_RATIO_MAX: CGFloat = 25.0
private let MATH_CONFIDENCE_GATE: Float = 0.85
private let LETTER_RUN_GATE = 4

private func looksLikeDrawing(_ bbox: CGRect) -> Bool {
    let width = bbox.width
    let height = bbox.height
    if max(width, height) < INK_MINIMUM_SPAN_PX { return true }
    let aspect = width / max(height, 0.001)
    if aspect < INK_ASPECT_RATIO_MIN { return true }
    return aspect > INK_ASPECT_RATIO_MAX
}

let latexCommandPattern = try! NSRegularExpression(pattern: "\\\\[a-zA-Z]+")
private let mathSymbolPattern = try! NSRegularExpression(pattern: "[0-9+=^_/*<>()&-]")
private let mathBracketPattern = try! NSRegularExpression(pattern: "[\\[\\]:,|{}]")
private let letterRunPattern = try! NSRegularExpression(pattern: "[a-zA-Z]+")
private let mathFunctionPattern = try! NSRegularExpression(
    pattern: "(?<![a-zA-Z])(?:arcsin|arccos|arctan|sqrt|sinh|cosh|tanh|log|ln|exp|sin|cos|tan|sec|csc|cot|lim|max|min|sup|inf|det|dim|deg|gcd|mod|arg)"
)
private let latexEnvPattern = try! NSRegularExpression(pattern: "\\\\(?:begin|end)\\{[a-zA-Z*]+\\}")

func longestLetterRun(_ content: String) -> Int {
    let range = NSRange(content.startIndex..., in: content)
    let stripped1 = latexEnvPattern.stringByReplacingMatches(in: content, range: range, withTemplate: " ")
    let range2 = NSRange(stripped1.startIndex..., in: stripped1)
    let stripped2 = latexCommandPattern.stringByReplacingMatches(in: stripped1, range: range2, withTemplate: " ")
    let range3 = NSRange(stripped2.startIndex..., in: stripped2)
    let stripped3 = mathFunctionPattern.stringByReplacingMatches(in: stripped2, range: range3, withTemplate: " ")

    let finalRange = NSRange(stripped3.startIndex..., in: stripped3)
    let matches = letterRunPattern.matches(in: stripped3, range: finalRange)
    var longest = 0
    for match in matches {
        longest = max(longest, match.range.length)
    }
    return longest
}

private func classifyKind(_ content: String) -> RecognizedKind {
    let range = NSRange(content.startIndex..., in: content)
    let stripped = latexCommandPattern.stringByReplacingMatches(in: content, range: range, withTemplate: " ")
    let strippedRange = NSRange(stripped.startIndex..., in: stripped)

    if latexCommandPattern.firstMatch(in: content, range: range) != nil { return .math }
    if mathSymbolPattern.firstMatch(in: stripped, range: strippedRange) != nil { return .math }
    if mathBracketPattern.firstMatch(in: stripped, range: strippedRange) != nil { return .math }
    return .text
}

func routeKind(content: String, confidence: Float) -> RecognizedKind {
    if confidence < MATH_CONFIDENCE_GATE { return .text }
    if longestLetterRun(content) >= LETTER_RUN_GATE { return .text }
    return classifyKind(content)
}

// MARK: - OCR Engine

private let IDLE_FIRE_SECONDS: TimeInterval = 0.8

final class OCREngine: ObservableObject {
    @Published var blocks: [RecognizedBlock] = []
    @Published var isModelReady = false

    private var ctcRecognizer: CTCRecognizer?
    private let digitalInkRecognizer = DigitalInkTextRecognizer()
    private var idleTimer: Timer?
    private var lastStrokeCount = 0
    private let sessionStart = Date()

    init() {
        loadModels()
    }

    private func loadModels() {
        do {
            ctcRecognizer = try CTCRecognizer()
        } catch {
            print("CTC model load failed: \(error)")
        }

        digitalInkRecognizer.ensureModelDownloaded { [weak self] success in
            DispatchQueue.main.async {
                self?.isModelReady = success && self?.ctcRecognizer != nil
            }
        }
    }

    func strokesChanged(_ strokes: [Stroke]) {
        idleTimer?.invalidate()
        if strokes.count == lastStrokeCount { return }
        lastStrokeCount = strokes.count

        idleTimer = Timer.scheduledTimer(withTimeInterval: IDLE_FIRE_SECONDS, repeats: false) { [weak self] _ in
            self?.runRecognition(on: strokes)
        }
    }

    private func strokesToCTCPoints(_ stroke: Stroke) -> [CTCPoint] {
        stroke.points.map { p in
            CTCPoint(x: Float(p.location.x), y: Float(p.location.y), t: Float(p.timestamp))
        }
    }

    private func runRecognition(on strokes: [Stroke]) {
        guard let ctcRecognizer else { return }

        let groups = groupStrokes(strokes)
        var newBlocks: [RecognizedBlock] = []
        let dispatchGroup = DispatchGroup()
        let recognizedAt = Date().timeIntervalSince(sessionStart)

        for (index, group) in groups.enumerated() {
            if looksLikeDrawing(group.bbox) { continue }

            let ctcStrokes: [[CTCPoint]] = group.strokeIndices.compactMap { idx in
                let points = strokesToCTCPoints(strokes[idx])
                return points.count >= 2 ? points : nil
            }

            guard !ctcStrokes.isEmpty else { continue }

            do {
                let ctcResult = try ctcRecognizer.recognize(strokes: ctcStrokes)
                let kind = routeGroup(content: ctcResult.text, tokenConfidences: ctcResult.tokens.map { $0.confidence }, strokes: ctcStrokes)

                if kind == .math {
                    let block = RecognizedBlock(
                        id: "block_\(index)",
                        kind: .math,
                        content: ctcResult.text,
                        confidence: ctcResult.confidence,
                        bbox: group.bbox,
                        strokeIndices: group.strokeIndices,
                        recognizedAt: recognizedAt,
                        tokens: ctcResult.tokens
                    )
                    newBlocks.append(block)
                } else {
                    dispatchGroup.enter()
                    let capturedIndex = index
                    let capturedGroup = group
                    let capturedTokens = ctcResult.tokens

                    digitalInkRecognizer.recognize(strokes: ctcStrokes) { text in
                        let content = text ?? ctcResult.text
                        let block = RecognizedBlock(
                            id: "block_\(capturedIndex)",
                            kind: .text,
                            content: content,
                            confidence: text != nil ? 1.0 : ctcResult.confidence,
                            bbox: capturedGroup.bbox,
                            strokeIndices: capturedGroup.strokeIndices,
                            recognizedAt: recognizedAt,
                            tokens: capturedTokens
                        )
                        newBlocks.append(block)
                        dispatchGroup.leave()
                    }
                }
            } catch {
                print("CTC recognition error: \(error)")
            }
        }

        dispatchGroup.notify(queue: .main) { [weak self] in
            let sorted = newBlocks.sorted { a, b in
                if a.bbox.minY != b.bbox.minY { return a.bbox.minY < b.bbox.minY }
                return a.bbox.minX < b.bbox.minX
            }
            self?.blocks = sorted
        }
    }
}
