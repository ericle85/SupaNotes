import UIKit

@Observable
final class SuggestionRunner {
    enum Status: Equatable {
        case idle
        case capturing
        case thinking
        case rendering
        case done(String) // raw LLM response
        case failed(String)
    }

    var status: Status = .idle
    var tokens: [OverlayToken] = []
    var renderedImage: UIImage?
    var debugImage: UIImage?

    private let client = AgentOllamaClient()
    private let tokenizer = OverlayTokenizer()
    private let renderer = KaTeXRenderer()

    /// Pre-load KaTeX webview.
    func warmUp() async {
        await renderer.warmUp()
    }

    /// Capture viewport, send to Ollama, parse response into tokens, render LaTeX.
    func suggest(captureToken: AgentCaptureToken) async {
        status = .capturing

        guard let image = captureToken.captureViewport?() else {
            status = .failed("Capture failed")
            return
        }

        debugImage = image
        status = .thinking

        do {
            let response = try await client.suggest(image: image)
            let parsed = tokenizer.tokenize(response)
            tokens = parsed
            print("[SuggestionRunner] tokens: \(parsed.map { "[\($0.type.rawValue)]\($0.value)" })")

            // Build full LaTeX string from tokens
            let fullLatex = parsed.map(\.displayLatex).joined(separator: "\\;")

            status = .rendering
            let rendered = try await renderer.render(latex: fullLatex, fontSize: 20)
            renderedImage = rendered
            status = .done(response)
        } catch {
            status = .failed(error.localizedDescription)
            print("[SuggestionRunner] error: \(error)")
        }
    }
}
