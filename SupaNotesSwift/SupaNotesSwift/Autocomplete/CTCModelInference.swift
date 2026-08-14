import CoreML
import Foundation

class CTCModelInference {
    private let model: MLModel
    private let vocab: [Int: String]
    private let vocabSize: Int

    init() throws {
        let config = MLModelConfiguration()
        config.computeUnits = .all
        guard let modelURL = Bundle.main.url(forResource: "CTCTransformer", withExtension: "mlmodelc")
                ?? Bundle.main.url(forResource: "CTCTransformer", withExtension: "mlpackage")
        else {
            throw NSError(domain: "CTCModelInference", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "CTCTransformer model not found in bundle"])
        }
        self.model = try MLModel(contentsOf: modelURL, configuration: config)
        self.vocab = loadVocab()

        if let outputDesc = model.modelDescription.outputDescriptionsByName["log_probs"],
           let constraint = outputDesc.multiArrayConstraint {
            self.vocabSize = constraint.shape.last?.intValue ?? 259
        } else {
            self.vocabSize = 259
        }
    }

    func transcribe(strokes: [[StrokePoint]]) throws -> String {
        let normalized = normalizeStrokes(strokes)
        let features = extractPointFeatures(normalized)
        let seqLen = features.count / FEATURE_DIM

        if seqLen == 0 {
            return ""
        }

        let featureArray = try MLMultiArray(
            shape: [1, seqLen as NSNumber, FEATURE_DIM as NSNumber],
            dataType: .float32
        )
        for i in 0..<(seqLen * FEATURE_DIM) {
            featureArray[i] = NSNumber(value: features[i])
        }

        let lengthArray = try MLMultiArray(shape: [1], dataType: .int32)
        lengthArray[0] = NSNumber(value: Int32(seqLen))

        let input = try MLDictionaryFeatureProvider(dictionary: [
            "features": MLFeatureValue(multiArray: featureArray),
            "length": MLFeatureValue(multiArray: lengthArray),
        ])

        let output = try model.prediction(from: input)

        guard let logProbsArray = output.featureValue(for: "log_probs")?.multiArrayValue,
              let outLenArray = output.featureValue(for: "output_length")?.multiArrayValue
        else {
            throw NSError(domain: "CTCModelInference", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Unexpected output format"])
        }

        let outLen = outLenArray[0].intValue
        let totalElements = outLen * vocabSize
        var logProbs = [Float](repeating: 0, count: totalElements)
        let ptr = logProbsArray.dataPointer.bindMemory(to: Float16.self, capacity: logProbsArray.count)
        for i in 0..<totalElements {
            logProbs[i] = Float(ptr[i])
        }

        return ctcGreedyDecode(
            logProbs: logProbs,
            seqLen: outLen,
            vocabSize: vocabSize,
            vocab: vocab
        )
    }
}
