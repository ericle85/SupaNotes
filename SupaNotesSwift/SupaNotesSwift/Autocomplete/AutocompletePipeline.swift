import Foundation

struct PipelineResult: Codable {
  let classification: String
  let transcription: String?
  let suggestion: String?
  let placement: String
}

private let cachedClassifier = Result { try ClassifierModelInference() }
private let cachedCTCModel = Result { try CTCModelInference() }

func runAutocompletePipeline(strokes: [[StrokePoint]]) async -> PipelineResult {
  do {
    let classifier = try cachedClassifier.get()
    let kind = try classifier.classify(strokes: strokes)
    print("[Pipeline] Classification: \(kind)")

    if kind == "scribble" || kind == "none" {
      print("[Pipeline] Skipping — classified as \(kind)")
      return PipelineResult(
        classification: kind, transcription: nil, suggestion: nil, placement: "N/A")
    }

    if kind == "google" {
      let transcription = try await recognizeDigitalInk(strokes: strokes)
      print("[Pipeline] Digital Ink transcription: \(transcription)")
      return PipelineResult(
        classification: kind, transcription: transcription, suggestion: nil, placement: "N/A")
    }

    let ctcModel = try cachedCTCModel.get()
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
      placement: mathSuggestion?.placement ?? "N/A")
  } catch {
    print("[Pipeline] Error: \(error.localizedDescription)")
    return PipelineResult(
      classification: "error", transcription: nil, suggestion: nil, placement: "N/A")
  }
}
