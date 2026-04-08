import Foundation

enum OverlayTokenType: String, Codable {
    case latex
    case word
}

struct OverlayToken: Identifiable {
    let id = UUID()
    let type: OverlayTokenType
    let value: String
    let displayLatex: String
}
