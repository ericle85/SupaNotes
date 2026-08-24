import Foundation
import LiteRTLM

final class TextSuggestionEngine {
  static let shared = TextSuggestionEngine()

  private var engine: Engine?
  private var prepareFailed = false

  private init() {}

  func prepare() async {
    if engine != nil { return }
    if prepareFailed { return }

    guard let modelPath = Bundle.main.path(forResource: "gemma-4-E2B-it-gpu", ofType: "litertlm")
    else {
      print("[TextSuggestion] gemma-4-E2B-it-gpu.litertlm not found in bundle")
      prepareFailed = true
      return
    }

    do {
      let config = try EngineConfig(modelPath: modelPath, backend: .gpu)
      let newEngine = Engine(engineConfig: config)
      try await newEngine.initialize()
      engine = newEngine
      print("[TextSuggestion] Engine ready")
    } catch {
      print("[TextSuggestion] Init failed: \(error)")
      prepareFailed = true
    }
  }

  func generateContinuation(text: String) async -> String? {
    await prepare()
    guard let engine else { return nil }

    do {
      let prompt =
        "You continue handwritten text. "
        + "Output the original text followed by a natural continuation. "
        + "Only output 5 words max, nothing else."
      let systemPrompt = Message(prompt, role: .system)
      let config = ConversationConfig(
        systemMessage: systemPrompt,
        samplerConfig: try SamplerConfig(topK: 40, topP: 0.95, temperature: 0.7)
      )
      let conversation = try await engine.createConversation(with: config)
      let response = try await conversation.sendMessage(
        Message(text),
        maxOutputTokens: 50
      )
      let result = response.toString
      if result.isEmpty { return nil }
      print("[TextSuggestion] Generated: \(result)")
      return result
    } catch {
      print("[TextSuggestion] Error: \(error)")
      return nil
    }
  }
}
