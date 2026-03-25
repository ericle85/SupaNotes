import CoreML
import Foundation

nonisolated class CTCModel: @unchecked Sendable {
    private let model: MLModel
    let vocab: [Int: String]
    let vocabSize: Int

    init() throws {
        let config = MLModelConfiguration()
        config.computeUnits = .all
        guard let modelURL = Bundle.main.url(forResource: "CTCTransformer", withExtension: "mlmodelc")
                ?? Bundle.main.url(forResource: "CTCTransformer", withExtension: "mlpackage")
        else {
            throw NSError(domain: "CTCModel", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Model not found in bundle"])
        }
        self.model = try MLModel(contentsOf: modelURL, configuration: config)
        self.vocab = loadVocab()
        self.vocabSize = 259
    }

    func predict(features: [Float], seqLen: Int, threshold: Float = 0.7) throws -> DecodeResult {
        let featureArray = try MLMultiArray(
            shape: [1, seqLen as NSNumber, FEATURE_DIM as NSNumber],
            dataType: .float32
        )
        let ptr = featureArray.dataPointer.bindMemory(to: Float.self, capacity: seqLen * FEATURE_DIM)
        for i in 0..<(seqLen * FEATURE_DIM) {
            ptr[i] = features[i]
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
            throw NSError(domain: "CTCModel", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Unexpected output format"])
        }

        let outLen = outLenArray[0].intValue
        let totalElements = outLen * vocabSize
        var logProbs = [Float](repeating: 0, count: totalElements)
        let outPtr = logProbsArray.dataPointer.bindMemory(to: Float16.self, capacity: logProbsArray.count)
        for i in 0..<totalElements {
            logProbs[i] = Float(outPtr[i])
        }

        return ctcGreedyDecode(
            logProbs: logProbs, seqLen: outLen, vocabSize: vocabSize,
            vocab: vocab, threshold: threshold
        )
    }
}
