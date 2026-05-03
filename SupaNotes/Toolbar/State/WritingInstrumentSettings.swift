import Foundation

struct WritingInstrumentSettings: Codable, Equatable {
    var width: CGFloat
    var presets: [CGFloat]

    static func pen() -> WritingInstrumentSettings {
        .init(width: 3, presets: [1, 3, 8])
    }

    static func eraser() -> WritingInstrumentSettings {
        .init(width: 40, presets: [20, 40, 80])
    }

    // Ignores unknown keys from older versions that stored pen style fields.
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
