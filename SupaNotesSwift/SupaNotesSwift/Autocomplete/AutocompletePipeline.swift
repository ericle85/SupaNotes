import Foundation

struct PipelineResult: Codable {
  let classification: String
  let transcription: String?
  let suggestion: String?
  let placement: String

  static func skip(_ kind: String) -> PipelineResult {
    PipelineResult(classification: kind, transcription: nil, suggestion: nil, placement: "N/A")
  }
}

private func classifyStrokes(_ strokes: [[StrokePoint]], cache: AutocompleteModelCache) throws
  -> String
{
  guard let classifier = cache.classifier else {
    throw NSError(domain: "AutocompleteModelCache", code: 1)
  }
  let kind = try classifier.classify(strokes: strokes)
  print("[Pipeline] Classification: \(kind)")
  return kind
}

private func getSuggestionGoogle(_ strokes: [[StrokePoint]], cache: AutocompleteModelCache)
  async throws -> PipelineResult
{
  guard let recognizer = cache.googleRecognizer else {
    throw NSError(domain: "AutocompleteModelCache", code: 2)
  }
  let transcription = try await recognizeDigitalInk(strokes: strokes, recognizer: recognizer)
  print("[Pipeline] Digital Ink transcription: \(transcription)")
  return PipelineResult(
    classification: "google", transcription: transcription, suggestion: nil, placement: "N/A")
}

private func getSuggestionMath(_ strokes: [[StrokePoint]], cache: AutocompleteModelCache) throws
  -> PipelineResult
{
  guard let ctcModel = cache.ctcModel else {
    throw NSError(domain: "AutocompleteModelCache", code: 3)
  }
  let transcription = try ctcModel.transcribe(strokes: strokes)
  print("[Pipeline] CTC transcription: \(transcription)")

  let mathSuggestion = fetchMathSuggestion(expression: transcription)
  print(
    "[Pipeline] Suggestion: \(mathSuggestion?.text ?? "none") (placement: \(mathSuggestion?.placement ?? "N/A"))"
  )

  return PipelineResult(
    classification: "math", transcription: transcription,
    suggestion: mathSuggestion?.text,
    placement: mathSuggestion?.placement ?? "N/A"
  )
}

func runAutocompletePipeline(strokes: [[StrokePoint]]) async -> PipelineResult {
  do {
    let cache = AutocompleteModelCache.shared
    try await cache.prepare()

    let kind = try classifyStrokes(strokes, cache: cache)

    if kind == "scribble" || kind == "none" {
      return .skip(kind)
    }
    if kind == "google" {
      return try await getSuggestionGoogle(strokes, cache: cache)
    }
    return try getSuggestionMath(strokes, cache: cache)
  } catch {
    print("[Pipeline] Error: \(error.localizedDescription)")
    return .skip("error")
  }
}
