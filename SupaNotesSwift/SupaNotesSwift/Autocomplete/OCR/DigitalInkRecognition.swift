import Foundation

#if !targetEnvironment(simulator)
    import MLKitDigitalInkRecognition

    typealias CachedDigitalInkRecognizer = DigitalInkRecognizer

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
                if let successObserver { NotificationCenter.default.removeObserver(successObserver) }
                if let failObserver { NotificationCenter.default.removeObserver(failObserver) }
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
                            domain: "DigitalInk", code: -1, userInfo: [NSLocalizedDescriptionKey: "Download failed"]
                        )
                continuation.resume(throwing: error)
            }

            let conditions = ModelDownloadConditions()
            modelManager.download(model, conditions: conditions)
        }
    }

    func makeDigitalInkRecognizer() throws -> CachedDigitalInkRecognizer {
        let identifier = DigitalInkRecognitionModelIdentifier(forLanguageTag: "en")!
        let model = DigitalInkRecognitionModel(modelIdentifier: identifier)
        let options = DigitalInkRecognizerOptions(model: model)
        return DigitalInkRecognizer.digitalInkRecognizer(options: options)
    }

    func recognizeDigitalInk(
        strokes: [[StrokePoint]], recognizer: CachedDigitalInkRecognizer
    ) async throws -> String {
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

        let result = try await recognizer.recognize(ink: ink)

        guard let topCandidate = result.candidates.first else {
            return ""
        }

        print("[DigitalInk] Recognized: \(topCandidate.text)")
        return topCandidate.text
    }

#else

    typealias CachedDigitalInkRecognizer = Any

    func downloadDigitalInkModelIfNeeded() async throws {}

    func makeDigitalInkRecognizer() throws -> CachedDigitalInkRecognizer {
        return ()
    }

    func recognizeDigitalInk(
        strokes _: [[StrokePoint]], recognizer _: CachedDigitalInkRecognizer
    ) async throws -> String {
        return ""
    }

#endif
