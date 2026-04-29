import Foundation

// MARK: - Pen Style (commented out — ballpoint only, no customization)
/*
enum PenStyle: String, Codable, CaseIterable, Identifiable {
    case fountain
    case ballpoint

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fountain: return "Fountain Pen"
        case .ballpoint: return "Ball Pen"
        }
    }

    var iconName: String {
        switch self {
        case .fountain: return "pencil.tip"
        case .ballpoint: return "pencil"
        }
    }
}
*/

struct WritingInstrumentSettings: Codable, Equatable {
    var width: CGFloat
    var presets: [CGFloat] // 3 elements
    // Pen customization (penStyle, tipSharpness, pressureSensitivity) commented out — ballpoint only.
    // var penStyle: PenStyle
    // var tipSharpness: CGFloat
    // var pressureSensitivity: CGFloat

    static func pen() -> WritingInstrumentSettings {
        .init(width: 3, presets: [1, 3, 8])
    }

    static func eraser() -> WritingInstrumentSettings {
        .init(width: 40, presets: [20, 40, 80])
    }

    // Backward-compatible decoder: unknown keys (penStyle, tipSharpness, pressureSensitivity) are ignored.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        width = try container.decode(CGFloat.self, forKey: .width)
        presets = try container.decode([CGFloat].self, forKey: .presets)
    }

    init(width: CGFloat, presets: [CGFloat]) {
        self.width = width
        self.presets = presets
    }
}
