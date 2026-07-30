import CoreML
import Foundation

let CTC_RESAMPLE_STEP: Float = 0.02
let CTC_MAX_SEQ_LEN = 2048
let CTC_FEATURE_DIM = 6
let CTC_BLANK_TOKEN = 0

struct CTCPoint {
    let x: Float
    let y: Float
    let t: Float
}

struct CTCTokenDetail {
    let token: String
    let confidence: Float
}

struct CTCDecodeResult {
    let text: String
    let tokens: [CTCTokenDetail]
    let confidence: Float
}

// MARK: - Preprocessing

func ctcNormalizeStrokes(_ strokes: [[CTCPoint]]) -> [[CTCPoint]] {
    guard !strokes.isEmpty else { return strokes }

    var minX: Float = .greatestFiniteMagnitude
    var minY: Float = .greatestFiniteMagnitude
    var maxX: Float = -.greatestFiniteMagnitude
    var maxY: Float = -.greatestFiniteMagnitude
    var minT: Float = .greatestFiniteMagnitude
    var maxT: Float = -.greatestFiniteMagnitude

    for stroke in strokes {
        for p in stroke {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
            minT = min(minT, p.t); maxT = max(maxT, p.t)
        }
    }

    let rangeX = maxX - minX
    let rangeY = maxY - minY
    var scale = max(rangeX, rangeY)
    if scale < 1e-6 { scale = 1.0 }
    let centerX = (minX + maxX) / 2.0
    let centerY = (minY + maxY) / 2.0

    var tRange = maxT - minT
    if tRange < 1e-6 { tRange = 1.0 }

    return strokes.map { stroke in
        stroke.map { p in
            CTCPoint(
                x: (p.x - centerX) / scale,
                y: (p.y - centerY) / scale,
                t: (p.t - minT) / tRange
            )
        }
    }
}

private func ctcResampleStroke(_ stroke: [CTCPoint], step: Float = CTC_RESAMPLE_STEP) -> [CTCPoint] {
    guard stroke.count >= 2 else { return stroke }

    var cumLen = [Float](repeating: 0, count: stroke.count)
    for i in 1..<stroke.count {
        let dx = stroke[i].x - stroke[i - 1].x
        let dy = stroke[i].y - stroke[i - 1].y
        cumLen[i] = cumLen[i - 1] + sqrt(dx * dx + dy * dy)
    }
    let totalLen = cumLen.last!

    if totalLen < 1e-8 {
        return [stroke[0]]
    }

    let nPoints = max(2, Int(ceil(totalLen / step)) + 1)
    var result = [CTCPoint]()
    result.reserveCapacity(nPoints)

    let xs = stroke.map { $0.x }
    let ys = stroke.map { $0.y }
    let ts = stroke.map { $0.t }

    for i in 0..<nPoints {
        let targetLen = totalLen * Float(i) / Float(nPoints - 1)
        let interpX = ctcLinearInterp(cumLen, xs, at: targetLen)
        let interpY = ctcLinearInterp(cumLen, ys, at: targetLen)
        let interpT = ctcLinearInterp(cumLen, ts, at: targetLen)
        result.append(CTCPoint(x: interpX, y: interpY, t: interpT))
    }

    return result
}

private func ctcLinearInterp(_ keys: [Float], _ values: [Float], at target: Float) -> Float {
    if target <= keys[0] { return values[0] }
    if target >= keys[keys.count - 1] { return values[values.count - 1] }

    var lo = 0, hi = keys.count - 1
    while lo < hi - 1 {
        let mid = (lo + hi) / 2
        if keys[mid] <= target { lo = mid } else { hi = mid }
    }

    let frac = (target - keys[lo]) / max(keys[hi] - keys[lo], 1e-10)
    return values[lo] + frac * (values[hi] - values[lo])
}

func ctcExtractPointFeatures(_ strokes: [[CTCPoint]]) -> [Float] {
    var allFeatures = [Float]()

    for (i, stroke) in strokes.enumerated() {
        let resampled = ctcResampleStroke(stroke)
        for j in 0..<resampled.count {
            let x = resampled[j].x
            let y = resampled[j].y
            let dx: Float = j > 0 ? resampled[j].x - resampled[j - 1].x : 0
            let dy: Float = j > 0 ? resampled[j].y - resampled[j - 1].y : 0
            let dt: Float = j > 0 ? resampled[j].t - resampled[j - 1].t : 0
            let penState: Float = (i > 0 && j == 0) ? 1.0 : 0.0
            allFeatures.append(contentsOf: [x, y, dx, dy, dt, penState])
        }
    }

    let maxFloats = CTC_MAX_SEQ_LEN * CTC_FEATURE_DIM
    if allFeatures.count > maxFloats {
        allFeatures = Array(allFeatures.prefix(maxFloats))
    }

    return allFeatures
}

// MARK: - Decoder

private func ctcLoadVocab() -> [Int: String] {
    guard let url = Bundle.main.url(forResource: "vocab", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let tok2idx = json["tok2idx"] as? [String: Int]
    else {
        return [:]
    }
    var idx2tok = [Int: String]()
    for (tok, idx) in tok2idx {
        idx2tok[idx] = tok
    }
    return idx2tok
}

private func ctcGreedyDecode(
    logProbs: [Float],
    seqLen: Int,
    vocabSize: Int,
    vocab: [Int: String]
) -> CTCDecodeResult {
    var decodedTokens = [(Int, Float)]()
    var prev = -1

    for t in 0..<seqLen {
        let offset = t * vocabSize
        var maxIdx = 0
        var maxVal: Float = logProbs[offset]

        for v in 1..<vocabSize {
            let val = logProbs[offset + v]
            if val > maxVal {
                maxVal = val
                maxIdx = v
            }
        }

        let confidence = exp(maxVal)

        if maxIdx != prev && maxIdx != CTC_BLANK_TOKEN {
            decodedTokens.append((maxIdx, confidence))
        } else if maxIdx == prev && maxIdx != CTC_BLANK_TOKEN {
            if let last = decodedTokens.last {
                decodedTokens[decodedTokens.count - 1] = (last.0, max(last.1, confidence))
            }
        }
        prev = maxIdx
    }

    var tokens = [CTCTokenDetail]()
    for (tokIdx, conf) in decodedTokens {
        let tokStr = vocab[tokIdx] ?? "?"
        tokens.append(CTCTokenDetail(token: tokStr, confidence: conf))
    }

    let text = tokens.map { $0.token }.joined()
    let overall: Float = tokens.isEmpty ? 0.0 : tokens.map { $0.confidence }.reduce(0, +) / Float(tokens.count)

    return CTCDecodeResult(text: text, tokens: tokens, confidence: overall)
}

// MARK: - Model

final class CTCRecognizer {
    private let model: MLModel
    private let vocab: [Int: String]
    private let vocabSize: Int

    init() throws {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndGPU
        guard let modelURL = Bundle.main.url(forResource: "CTCTransformer", withExtension: "mlmodelc")
                ?? Bundle.main.url(forResource: "CTCTransformer", withExtension: "mlpackage")
        else {
            throw NSError(domain: "CTCRecognizer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model not found"])
        }
        self.model = try MLModel(contentsOf: modelURL, configuration: config)
        self.vocab = ctcLoadVocab()

        if let outputDesc = model.modelDescription.outputDescriptionsByName["log_probs"],
           let constraint = outputDesc.multiArrayConstraint {
            self.vocabSize = constraint.shape.last?.intValue ?? 259
        } else {
            self.vocabSize = 259
        }
    }

    func recognize(strokes: [[CTCPoint]]) throws -> CTCDecodeResult {
        let normalized = ctcNormalizeStrokes(strokes)
        let features = ctcExtractPointFeatures(normalized)
        let seqLen = features.count / CTC_FEATURE_DIM

        if seqLen == 0 {
            return CTCDecodeResult(text: "", tokens: [], confidence: 0)
        }

        let featureArray = try MLMultiArray(shape: [1, seqLen as NSNumber, CTC_FEATURE_DIM as NSNumber], dataType: .float32)
        for i in 0..<(seqLen * CTC_FEATURE_DIM) {
            featureArray[i] = NSNumber(value: features[i])
        }

        let lengthArray = try MLMultiArray(shape: [1], dataType: .float32)
        lengthArray[0] = NSNumber(value: Float(seqLen))

        let input = try MLDictionaryFeatureProvider(dictionary: [
            "features": MLFeatureValue(multiArray: featureArray),
            "length": MLFeatureValue(multiArray: lengthArray),
        ])

        let output = try model.prediction(from: input)

        guard let logProbsArray = output.featureValue(for: "log_probs")?.multiArrayValue,
              let outLenArray = output.featureValue(for: "output_length")?.multiArrayValue
        else {
            throw NSError(domain: "CTCRecognizer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unexpected output"])
        }

        let outLen = outLenArray[0].intValue
        let totalElements = outLen * vocabSize
        var logProbs = [Float](repeating: 0, count: totalElements)
        let ptr = logProbsArray.dataPointer.bindMemory(to: Float16.self, capacity: logProbsArray.count)
        for i in 0..<totalElements {
            logProbs[i] = Float(ptr[i])
        }

        return ctcGreedyDecode(logProbs: logProbs, seqLen: outLen, vocabSize: vocabSize, vocab: vocab)
    }
}
