import Foundation
import MLKitDigitalInkRecognition

func downloadDigitalInkModelIfNeeded() async throws {
  let identifier = DigitalInkRecognitionModelIdentifier(forLanguageTag: "en")!
  let model = DigitalInkRecognitionModel(modelIdentifier: identifier)
  let modelManager = ModelManager.modelManager()

  if modelManager.isModelDownloaded(model) {
    return
  }

  try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
    var successObserver: NSObjectProtocol?
    var failObserver: NSObjectProtocol?

    func removeObservers() {
      if let s = successObserver { NotificationCenter.default.removeObserver(s) }
      if let f = failObserver { NotificationCenter.default.removeObserver(f) }
    }

    successObserver = NotificationCenter.default.addObserver(
      forName: .mlkitModelDownloadDidSucceed,
      object: nil,
      queue: nil
    ) { _ in
      removeObservers()
      continuation.resume()
    }

    failObserver = NotificationCenter.default.addObserver(
      forName: .mlkitModelDownloadDidFail,
      object: nil,
      queue: nil
    ) { notification in
      removeObservers()
      let error =
        notification.userInfo?[ModelDownloadUserInfoKey.error.rawValue] as? Error
        ?? NSError(
          domain: "DigitalInk", code: -1, userInfo: [NSLocalizedDescriptionKey: "Download failed"])
      continuation.resume(throwing: error)
    }

    let conditions = ModelDownloadConditions()
    modelManager.download(model, conditions: conditions)
  }
}

func recognizeDigitalInk(strokes: [[StrokePoint]]) async throws -> String {
  try await downloadDigitalInkModelIfNeeded()

  let inkStrokes: [MLKitDigitalInkRecognition.Stroke] = strokes.map { points in
    let mlPoints = points.map { point in
      MLKitDigitalInkRecognition.StrokePoint(
        x: point.x,
        y: point.y,
        t: Int(point.t * 1000)
      )
    }
    return MLKitDigitalInkRecognition.Stroke(points: mlPoints)
  }
  let ink = Ink(strokes: inkStrokes)

  let identifier = DigitalInkRecognitionModelIdentifier(forLanguageTag: "en")!
  let model = DigitalInkRecognitionModel(modelIdentifier: identifier)
  let options = DigitalInkRecognizerOptions(model: model)
  let recognizer = DigitalInkRecognizer.digitalInkRecognizer(options: options)

  let result = try await recognizer.recognize(ink: ink)

  guard let topCandidate = result.candidates.first else {
    return ""
  }

  print("[DigitalInk] Recognized: \(topCandidate.text)")
  return topCandidate.text
}
