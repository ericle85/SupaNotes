import Testing
import Foundation
@testable import SupaNotes

struct WritingInstrumentSettingsTests {

    // MARK: - Factory defaults

    @Test func pen_hasExpectedDefaults() {
        let pen = WritingInstrumentSettings.pen()
        #expect(pen.width == 3)
        #expect(pen.presets == [1, 3, 8])
        #expect(pen.presets.count == 3)
    }

    @Test func eraser_hasExpectedDefaults() {
        let eraser = WritingInstrumentSettings.eraser()
        #expect(eraser.width == 40)
        #expect(eraser.presets == [20, 40, 80])
        #expect(eraser.presets.count == 3)
    }

    @Test func highlighter_hasExpectedDefaults() {
        let highlighter = WritingInstrumentSettings.highlighter()
        #expect(highlighter.width == 15)
        #expect(highlighter.presets == [8, 15, 25])
        #expect(highlighter.presets.count == 3)
    }

    // MARK: - Default width is a preset

    @Test func pen_defaultWidthIsAPreset() {
        let pen = WritingInstrumentSettings.pen()
        #expect(pen.presets.contains(pen.width))
    }

    @Test func eraser_defaultWidthIsAPreset() {
        let eraser = WritingInstrumentSettings.eraser()
        #expect(eraser.presets.contains(eraser.width))
    }

    @Test func highlighter_defaultWidthIsAPreset() {
        let highlighter = WritingInstrumentSettings.highlighter()
        #expect(highlighter.presets.contains(highlighter.width))
    }

    // MARK: - Codable round-trip

    @Test func codable_roundTrip_preservesValues() throws {
        let original = WritingInstrumentSettings.pen()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WritingInstrumentSettings.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - Equatable

    @Test func equatable_sameValues_areEqual() {
        let a = WritingInstrumentSettings.pen()
        let b = WritingInstrumentSettings.pen()
        #expect(a == b)
    }

    @Test func equatable_differentValues_areNotEqual() {
        let a = WritingInstrumentSettings.pen()
        let b = WritingInstrumentSettings.eraser()
        #expect(a != b)
    }
}
