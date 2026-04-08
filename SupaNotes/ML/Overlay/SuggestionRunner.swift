import UIKit

@Observable
final class SuggestionRunner {
    enum Status: Equatable {
        case idle
        case capturing
        case thinking
        case rendering
        case done(String)
        case failed(String)
    }

    var status: Status = .idle
    var tokens: [OverlayToken] = []
    /// Pre-rendered images for latex tokens (keyed by token id)
    var latexImages: [UUID: UIImage] = [:]

    private let client = AgentOllamaClient()
    private let tokenizer = OverlayTokenizer()
    private let mathRenderer = SwiftMathRenderer()

    func suggest(captureToken: AgentCaptureToken) async {
        status = .capturing

        guard let image = captureToken.captureViewport?() else {
            status = .failed("Capture failed")
            return
        }

        status = .thinking

        do {
            let response = try await client.suggest(image: image)
            print("[SuggestionRunner] model output: \(response)")
            let parsed = tokenizer.tokenize(response)
            tokens = parsed

            // Pre-render latex tokens with SwiftMath
            status = .rendering
            let fontSize: CGFloat = 48
            var images: [UUID: UIImage] = [:]
            for token in parsed where token.type == .latex {
                if let result = mathRenderer.render(latex: token.value, fontSize: fontSize) {
                    images[token.id] = result.image
                }
            }
            latexImages = images

            status = .done(response)
        } catch {
            status = .failed(error.localizedDescription)
            print("[SuggestionRunner] error: \(error)")
        }
    }
}
