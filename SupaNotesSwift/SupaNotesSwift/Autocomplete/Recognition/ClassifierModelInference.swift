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
    for i in 0..<(CLASSIFIER_SEQ_LEN * 2) {
      inputArray[i] = NSNumber(value: normalized[i])
    }

    let input = try MLDictionaryFeatureProvider(dictionary: [
      "sequence": MLFeatureValue(multiArray: inputArray)
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
    for i in 0..<CLASSIFIER_CLASSES.count {
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
  let finitePoints = strokes.flatMap { $0 }.filter { $0.x.isFinite && $0.y.isFinite }

  if finitePoints.isEmpty {
    return [Float](repeating: 0, count: CLASSIFIER_SEQ_LEN * 2)
  }

  let bbox = strokeBoundingBox(finitePoints)
  let normalizedX = finitePoints.map { ($0.x - bbox.minX) / bbox.spanX * 2.0 - 1.0 }
  let normalizedY = finitePoints.map { ($0.y - bbox.minY) / bbox.spanY * 2.0 - 1.0 }

  let resampled = resampleToFixedLength(normalizedX, normalizedY, count: CLASSIFIER_SEQ_LEN)

  var result = [Float](repeating: 0, count: CLASSIFIER_SEQ_LEN * 2)
  for i in 0..<CLASSIFIER_SEQ_LEN {
    result[i * 2] = resampled.xs[i]
    result[i * 2 + 1] = resampled.ys[i]
  }
  return result
}
