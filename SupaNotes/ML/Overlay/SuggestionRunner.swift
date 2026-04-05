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
    var characters: [OverlayCharacter] = []
    var renderedImage: UIImage?
    var renderSize: CGSize = .zero
    var debugImage: UIImage?

    private let client = AgentOllamaClient()
    private let tokenizer = OverlayTokenizer()
    private let parser = MathParser()
    private let layoutEngine = MathLayoutEngine()

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

            // Parse tokens into MathNode tree
            var allNodes: [MathNode] = []
            for token in parsed {
                switch token.type {
                case .latex:
                    allNodes.append(contentsOf: parser.parse(token.value))
                case .word:
                    allNodes.append(.text(token.value))
                    allNodes.append(.space)
                }
            }

            // Layout and render
            status = .rendering
            let fontSize: CGFloat = 48 // TODO: adapt to user's stroke height
            let result = layoutEngine.layout(nodes: allNodes, fontSize: fontSize)
            renderedImage = result.image
            renderSize = result.size
            characters = result.characters

            print("[SuggestionRunner] \(result.characters.count) characters, size: \(result.size)")
            status = .done(response)
        } catch {
            status = .failed(error.localizedDescription)
            print("[SuggestionRunner] error: \(error)")
        }
    }
}
