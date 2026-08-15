import Foundation

func runAutocompletePipeline(strokes: [[StrokePoint]]) async -> String {
    do {
        let classifier = try ClassifierModelInference()
        let kind = try classifier.classify(strokes: strokes)
        print("[Pipeline] Classification: \(kind)")

        if kind == "scribble" || kind == "none" {
            print("[Pipeline] Skipping — classified as \(kind)")
            return kind
        }

        if kind == "google" {
            let transcription = try await recognizeDigitalInk(strokes: strokes)
            print("[Pipeline] Digital Ink transcription: \(transcription)")
            return kind
        }

        let ctcModel = try CTCModelInference()
        let transcription = try ctcModel.transcribe(strokes: strokes)
        print("[Pipeline] CTC transcription: \(transcription)")

        if let suggestion = fetchMathSuggestion(expression: transcription) {
            print("[Pipeline] Suggestion: \(suggestion)")
        } else {
            print("[Pipeline] No suggestion returned")
        }

        return kind
    } catch {
        print("[Pipeline] Error: \(error.localizedDescription)")
        return "error"
    }
}
