import Foundation

struct TextSuggestion {
  let text: String
  let currentText: String
  let anchorX: CGFloat
  let lineYCenter: CGFloat
  let lineHeight: CGFloat
}

func ocr(strokes: [[StrokePoint]]) async throws -> String {
  let cache = AutocompleteModelCache.shared
  try await cache.prepare()

  guard let classifier = cache.classifier else { return "" }
  let kind = try classifier.classify(strokes: strokes)
  print("[OCR] Classification: \(kind)")

  if kind == "math" {
    guard let ctcModel = cache.ctcModel else { return "" }
    let transcription = try ctcModel.transcribe(strokes: strokes)
    print("[OCR] CTC transcription: \(transcription)")
    return transcription
  }

  if kind == "google" {
    guard let recognizer = cache.googleRecognizer else { return "" }
    let transcription = try await recognizeDigitalInk(
      strokes: strokes, recognizer: recognizer)
    print("[OCR] Digital Ink transcription: \(transcription)")
    return transcription
  }

  return ""
}

func generateSuggestion(
  strokes: [[StrokePoint]]
) async -> TextSuggestion? {
  do {
    let currentText = try await ocr(strokes: strokes)
    if currentText.isEmpty { return nil }

    guard
      let fullSuggestion = await TextSuggestionEngine.shared
        .generateContinuation(text: currentText)
    else {
      return nil
    }

    guard let ghostText = chopMatchingPrefix(
      suggestion: fullSuggestion, currentText: currentText)
    else {
      return nil
    }

    let placement = computePlacement(strokes: strokes)
    return TextSuggestion(
      text: ghostText,
      currentText: currentText,
      anchorX: placement.anchorX,
      lineYCenter: placement.yCenter,
      lineHeight: placement.height
    )
  } catch {
    print("[Suggestion] Error: \(error)")
    return nil
  }
}

private func computePlacement(
  strokes: [[StrokePoint]]
) -> (anchorX: CGFloat, yCenter: CGFloat, height: CGFloat) {
  var maxX: Float = 0
  var minY: Float = .greatestFiniteMagnitude
  var maxY: Float = -.greatestFiniteMagnitude

  for stroke in strokes {
    for point in stroke {
      if point.x > maxX { maxX = point.x }
      if point.y < minY { minY = point.y }
      if point.y > maxY { maxY = point.y }
    }
  }

  let height = CGFloat(maxY - minY)
  let yCenter = CGFloat(minY + maxY) / 2
  return (CGFloat(maxX), yCenter, height)
}

private func chopMatchingPrefix(
  suggestion: String, currentText: String
) -> String? {
  let lowerSuggestion = suggestion.lowercased()
  let lowerCurrent = currentText.lowercased()

  guard lowerSuggestion.hasPrefix(lowerCurrent) else { return nil }

  let remainder = String(suggestion.dropFirst(currentText.count))
  if remainder.trimmingCharacters(in: .whitespaces).isEmpty {
    return nil
  }
  return remainder
}
