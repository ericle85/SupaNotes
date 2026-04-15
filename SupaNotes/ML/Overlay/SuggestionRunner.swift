import UIKit
import AgentKit

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
            guard let png = image.pngData() else { throw AgentError.invalidResponse }
            let response = try await client.suggest(imagePNG: png)
            print("[SuggestionRunner] model output: \(response)")

            let (finalTokens, images) = try await renderWithRetry(image: image, response: response)
            tokens = finalTokens
            latexImages = images
            let finalResponse = finalTokens.map(\.value).joined(separator: " ")
            status = .done(finalResponse)
        } catch {
            status = .failed(error.localizedDescription)
            print("[SuggestionRunner] error: \(error)")
        }
    }

    // MARK: - Private

    private let maxRetries = 3

    /// Returns (tokens, images) - tokens and their rendered images with matching UUIDs
    private func renderWithRetry(image: UIImage, response: String) async throws -> ([OverlayToken], [UUID: UIImage]) {
        let fontSize: CGFloat = 48
        var currentResponse = response
        var attempt = 0

        while attempt < maxRetries {
            let parsed = tokenizer.tokenize(currentResponse)
            let (images, failures) = renderTokensWithValidation(parsed, fontSize: fontSize)

            guard !failures.isEmpty else {
                // Return tokens with matching image UUIDs
                return (parsed, images)
            }

            attempt += 1
            if attempt >= maxRetries {
                print("[SuggestionRunner] max retries reached, returning partial result")
                return (parsed, images)
            }

            print("[SuggestionRunner] render failures (attempt \(attempt)/\(maxRetries)): \(failures)")
            guard let png = image.pngData() else { throw AgentError.invalidResponse }
            currentResponse = try await client.suggest(imagePNG: png, renderFeedback: failures)
            print("[SuggestionRunner] retry output: \(currentResponse)")
        }

        return ([], [:])
    }

    /// Render tokens with validation, returning images and detailed failure info
    private func renderTokensWithValidation(_ tokens: [OverlayToken], fontSize: CGFloat) -> (images: [UUID: UIImage], failures: [String]) {
        var images: [UUID: UIImage] = [:]
        var failures: [String] = []

        for token in tokens where token.type == .latex {
            let (result, validation) = mathRenderer.validateAndRender(
                latex: token.value,
                fontSize: fontSize
            )

            if let result = result {
                images[token.id] = result.image
                print("[SuggestionRunner] render SUCCESS for: \(token.value.prefix(40))...")
            } else {
                // Build detailed error message for model feedback
                let errorDetail = validation.errorDescription ?? "render failed"
                failures.append("- \(token.value): \(errorDetail)")
                print("[SuggestionRunner] render FAILED: \(errorDetail)")
            }
        }
        return (images, failures)
    }
}
