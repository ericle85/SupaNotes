import Foundation

func runOCRPipeline(strokes: [[StrokePoint]]) async {
    do {
        let cache = AutocompleteModelCache.shared
        try await cache.prepare()

        guard let classifier = cache.classifier else { return }
        let kind = try classifier.classify(strokes: strokes)
        print("[OCR] Classification: \(kind)")

        if kind == "math" {
            guard let ctcModel = cache.ctcModel else { return }
            let transcription = try ctcModel.transcribe(strokes: strokes)
            print("[OCR] CTC transcription: \(transcription)")
        }

        if kind == "google" {
            guard let recognizer = cache.googleRecognizer else { return }
            let transcription = try await recognizeDigitalInk(strokes: strokes, recognizer: recognizer)
            print("[OCR] Digital Ink transcription: \(transcription)")
        }
    } catch {
        print("[OCR] Error: \(error.localizedDescription)")
    }
}
