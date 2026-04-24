import Foundation

// Pen rendering style that controls how pressure maps to stroke width.
// Pen rendering style — ballpoint is uniform width, fountain is pressure-sensitive.
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

    // SF Symbol name for each pen style.
    var iconName: String {
        switch self {
        case .fountain: return "pencil.tip"
        case .ballpoint: return "pencil"
        }
    }
}

struct WritingInstrumentSettings: Codable, Equatable {
    var width: CGFloat
    var presets: [CGFloat] // 3 elements
    // Which pen rendering curve to use.
    var penStyle: PenStyle
    // How thin the stroke gets at low pressure (0 = flat, 1 = very sharp taper).
    var tipSharpness: CGFloat
    // How much Apple Pencil pressure affects stroke width (0 = none, 1 = max).
    var pressureSensitivity: CGFloat

    static func pen() -> WritingInstrumentSettings {
        .init(width: 3, presets: [1, 3, 8], penStyle: .ballpoint, tipSharpness: 0.5, pressureSensitivity: 0.5)
    }

    static func eraser() -> WritingInstrumentSettings {
        .init(width: 40, presets: [20, 40, 80], penStyle: .ballpoint, tipSharpness: 0.5, pressureSensitivity: 0.5)
    }

    // Backward-compatible decoder: missing keys fall back to defaults.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        width = try container.decode(CGFloat.self, forKey: .width)
        presets = try container.decode([CGFloat].self, forKey: .presets)
        penStyle = try container.decodeIfPresent(PenStyle.self, forKey: .penStyle) ?? .ballpoint
        tipSharpness = try container.decodeIfPresent(CGFloat.self, forKey: .tipSharpness) ?? 0.5
        pressureSensitivity = try container.decodeIfPresent(CGFloat.self, forKey: .pressureSensitivity) ?? 0.5
    }

    init(width: CGFloat, presets: [CGFloat], penStyle: PenStyle = .ballpoint, tipSharpness: CGFloat = 0.5, pressureSensitivity: CGFloat = 0.5) {
        self.width = width
        self.presets = presets
        self.penStyle = penStyle
        self.tipSharpness = tipSharpness
        self.pressureSensitivity = pressureSensitivity
    }
}
