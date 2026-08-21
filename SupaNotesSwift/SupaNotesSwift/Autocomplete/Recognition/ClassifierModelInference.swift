import CoreML
import Foundation

let CLASSIFIER_SEQ_LEN = 160
let CLASSIFIER_CLASSES = ["math", "google", "scribble", "none"]

class ClassifierModelInference {
    private let model: MLModel

    init() throws {
        let config = MLModelConfiguration()
        config.computeUnits = .all
        guard
            let modelURL = Bundle.main.url(forResource: "StrokeClassifier", withExtension: "mlmodelc")
            ?? Bundle.main.url(forResource: "StrokeClassifier", withExtension: "mlpackage")
        else {
            throw NSError(
                domain: "ClassifierModelInference", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "StrokeClassifier model not found in bundle"]
            )
        }
        model = try MLModel(contentsOf: modelURL, configuration: config)
    }

    func classify(strokes: [[StrokePoint]]) throws -> String {
        let normalized = normalizeSequenceForClassifier(strokes)
        let inputArray = try MLMultiArray(
            shape: [1, CLASSIFIER_SEQ_LEN as NSNumber, 2],
            dataType: .float32
        )
        for i in 0 ..< (CLASSIFIER_SEQ_LEN * 2) {
            inputArray[i] = NSNumber(value: normalized[i])
        }

        let input = try MLDictionaryFeatureProvider(dictionary: [
            "sequence": MLFeatureValue(multiArray: inputArray),
        ])
        let output = try model.prediction(from: input)

        guard let probsArray = output.featureValue(for: "class_probabilities")?.multiArrayValue else {
            throw NSError(
                domain: "ClassifierModelInference", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unexpected output format"]
            )
        }

        var maxIdx = 0
        var maxVal: Float = -Float.greatestFiniteMagnitude
        for i in 0 ..< CLASSIFIER_CLASSES.count {
            let val = probsArray[i].floatValue
            if val > maxVal {
                maxVal = val
                maxIdx = i
            }
        }
        return CLASSIFIER_CLASSES[maxIdx]
    }
}

func normalizeSequenceForClassifier(_ strokes: [[StrokePoint]]) -> [Float] {
    var allXY = [Float]()
    for stroke in strokes {
        for p in stroke {
            if p.x.isFinite, p.y.isFinite {
                allXY.append(p.x)
                allXY.append(p.y)
            }
        }
    }

    let pointCount = allXY.count / 2
    if pointCount == 0 {
        return [Float](repeating: 0, count: CLASSIFIER_SEQ_LEN * 2)
    }

    var minX: Float = .greatestFiniteMagnitude
    var minY: Float = .greatestFiniteMagnitude
    var maxX: Float = -.greatestFiniteMagnitude
    var maxY: Float = -.greatestFiniteMagnitude
    for i in 0 ..< pointCount {
        let x = allXY[i * 2]
        let y = allXY[i * 2 + 1]
        minX = min(minX, x)
        maxX = max(maxX, x)
        minY = min(minY, y)
        maxY = max(maxY, y)
    }

    var spanX = maxX - minX
    var spanY = maxY - minY
    if spanX < 1e-5 { spanX = 1e-5 }
    if spanY < 1e-5 { spanY = 1e-5 }

    var normalizedX = [Float](repeating: 0, count: pointCount)
    var normalizedY = [Float](repeating: 0, count: pointCount)
    for i in 0 ..< pointCount {
        normalizedX[i] = (allXY[i * 2] - minX) / spanX * 2.0 - 1.0
        normalizedY[i] = (allXY[i * 2 + 1] - minY) / spanY * 2.0 - 1.0
    }

    var result = [Float](repeating: 0, count: CLASSIFIER_SEQ_LEN * 2)
    for i in 0 ..< CLASSIFIER_SEQ_LEN {
        let srcIdx = Float(i) / Float(CLASSIFIER_SEQ_LEN - 1) * Float(pointCount - 1)
        let lo = Int(srcIdx)
        let hi = min(lo + 1, pointCount - 1)
        let frac = srcIdx - Float(lo)
        result[i * 2] = normalizedX[lo] + frac * (normalizedX[hi] - normalizedX[lo])
        result[i * 2 + 1] = normalizedY[lo] + frac * (normalizedY[hi] - normalizedY[lo])
    }

    return result
}
