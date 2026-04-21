import Foundation

struct WritingInstrumentSettings: Codable, Equatable {
    var width: CGFloat
    var presets: [CGFloat] // 3 elements

    static func pen() -> WritingInstrumentSettings {
        .init(width: 3, presets: [1, 3, 8])
    }

    static func eraser() -> WritingInstrumentSettings {
        .init(width: 40, presets: [20, 40, 80])
    }

    static func highlighter() -> WritingInstrumentSettings {
        .init(width: 15, presets: [8, 15, 25])
    }
}
