import Foundation

enum OverlayTokenType: String, Codable {
    case latex
    case word
}

struct OverlayToken: Identifiable {
    let id = UUID()
    let type: OverlayTokenType
    let value: String      // raw content for matching
    let displayLatex: String // for rendering (words wrapped in \text{})
}
