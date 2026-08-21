import Foundation

struct PipelineResult: Codable {
    let classification: String
    let transcription: String?
    let suggestion: String?
    let placement: String
}

func runAutocompletePipeline(strokes: [[StrokePoint]]) async -> PipelineResult {
    do {
        let modelCache = AutocompleteModelCache.shared
        try await modelCache.prepare()

        guard let classifier = modelCache.classifier else {
            throw NSError(domain: "AutocompleteModelCache", code: 1)
        }
        let kind = try classifier.classify(strokes: strokes)
        print("[Pipeline] Classification: \(kind)")

        if kind == "scribble" || kind == "none" {
            print("[Pipeline] Skipping — classified as \(kind)")
            return PipelineResult(
                classification: kind, transcription: nil, suggestion: nil, placement: "N/A"
            )
        }

        if kind == "google" {
            guard let googleRecognizer = modelCache.googleRecognizer else {
                throw NSError(domain: "AutocompleteModelCache", code: 2)
            }
            let transcription = try await recognizeDigitalInk(
                strokes: strokes, recognizer: googleRecognizer
            )
            print("[Pipeline] Digital Ink transcription: \(transcription)")
            return PipelineResult(
                classification: kind, transcription: transcription, suggestion: nil, placement: "N/A"
            )
        }

        guard let ctcModel = modelCache.ctcModel else {
            throw NSError(domain: "AutocompleteModelCache", code: 3)
        }
        let transcription = try ctcModel.transcribe(strokes: strokes)
        print("[Pipeline] CTC transcription: \(transcription)")

        let mathSuggestion = fetchMathSuggestion(expression: transcription)
        if let mathSuggestion {
            print("[Pipeline] Suggestion: \(mathSuggestion.text) (placement: \(mathSuggestion.placement))")
        } else {
            print("[Pipeline] No suggestion returned")
        }

        return PipelineResult(
            classification: kind, transcription: transcription,
            suggestion: mathSuggestion?.text,
            placement: mathSuggestion?.placement ?? "N/A"
        )
    } catch {
        print("[Pipeline] Error: \(error.localizedDescription)")
        return PipelineResult(
            classification: "error", transcription: nil, suggestion: nil, placement: "N/A"
        )
    }
}
