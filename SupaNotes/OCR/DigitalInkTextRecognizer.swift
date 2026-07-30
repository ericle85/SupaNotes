import Foundation
import MLKitDigitalInkRecognition
import MLKitCommon

typealias InkStrokePoint = MLKitDigitalInkRecognition.StrokePoint
typealias InkStroke = MLKitDigitalInkRecognition.Stroke

final class DigitalInkTextRecognizer {
    private var recognizer: DigitalInkRecognizer?
    private let modelIdentifier: DigitalInkRecognitionModelIdentifier

    init() {
        guard let identifier = DigitalInkRecognitionModelIdentifier(forLanguageTag: "en-US") else {
            fatalError("en-US digital ink model identifier not found")
        }
        self.modelIdentifier = identifier
    }

    func ensureModelDownloaded(completion: @escaping (Bool) -> Void) {
        let model = DigitalInkRecognitionModel(modelIdentifier: modelIdentifier)
        let manager = ModelManager.modelManager()

        if manager.isModelDownloaded(model) {
            let options = DigitalInkRecognizerOptions(model: model)
            recognizer = DigitalInkRecognizer.digitalInkRecognizer(options: options)
            completion(true)
            return
        }

        manager.download(model, conditions: ModelDownloadConditions())
        NotificationCenter.default.addObserver(
            forName: .mlkitModelDownloadDidSucceed,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            let options = DigitalInkRecognizerOptions(model: model)
            self.recognizer = DigitalInkRecognizer.digitalInkRecognizer(options: options)
            completion(true)
        }
        NotificationCenter.default.addObserver(
            forName: .mlkitModelDownloadDidFail,
            object: nil,
            queue: nil
        ) { _ in
            print("ML Kit model download failed")
            completion(false)
        }
    }

    func recognize(strokes: [[CTCPoint]], completion: @escaping (String?) -> Void) {
        guard let recognizer else {
            completion(nil)
            return
        }

        let inkStrokes: [InkStroke] = strokes.map { points in
            let inkPoints = points.map { p in
                InkStrokePoint(x: p.x, y: p.y, t: Int(p.t * 1000))
            }
            return InkStroke(points: inkPoints)
        }

        let ink = Ink(strokes: inkStrokes)
        recognizer.recognize(ink: ink) { result, error in
            if let error {
                print("Digital ink recognition error: \(error.localizedDescription)")
                completion(nil)
                return
            }
            completion(result?.candidates.first?.text)
        }
    }
}
