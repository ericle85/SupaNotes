import Testing
import Foundation
@testable import SupaNotes

/// Tests for WritingInstrumentSettings
/// Each tool (pen, eraser, highlighter) has settings like width and preset sizes
/// Users can quickly switch between preset widths for each tool
@Suite struct WritingInstrumentSettingsTests {

    // MARK: - Factory defaults
    // Tests that each tool has the correct default width and preset options

    @Test func pen_hasExpectedDefaults() {
        // The pen should have these specific default settings
        let pen = WritingInstrumentSettings.pen()
        #expect(pen.width == 3)                     // Default pen width is 3 pixels
        #expect(pen.presets == [1, 3, 8])          // Preset sizes: thin, medium, thick
        #expect(pen.presets.count == 3)             // Exactly 3 preset options
    }

    @Test func eraser_hasExpectedDefaults() {
        // The eraser should be thicker than a pen
        let eraser = WritingInstrumentSettings.eraser()
        #expect(eraser.width == 40)                 // Default eraser width is 40 pixels
        #expect(eraser.presets == [20, 40, 80])    // Preset sizes: small, medium, large
        #expect(eraser.presets.count == 3)          // Exactly 3 preset options
    }

    // MARK: - Default width is a preset
    // Tests that the default width is always one of the available presets
    // (This ensures the width selector UI works correctly)

    @Test func pen_defaultWidthIsAPreset() {
        // The pen's default width should be selectable from the presets
        let pen = WritingInstrumentSettings.pen()
        // Check that 3 (the default) is in the preset list [1, 3, 8]
        #expect(pen.presets.contains(pen.width))
    }

    @Test func eraser_defaultWidthIsAPreset() {
        // The eraser's default width should be selectable from the presets
        let eraser = WritingInstrumentSettings.eraser()
        // Check that 40 (the default) is in the preset list [20, 40, 80]
        #expect(eraser.presets.contains(eraser.width))
    }

    // MARK: - Codable round-trip
    // Tests that settings can be saved to JSON and loaded back without losing data

    @Test func codable_roundTrip_preservesValues() throws {
        // Create a pen's settings
        let original = WritingInstrumentSettings.pen()

        // Encode it to JSON (simulating saving to a file)
        let data = try JSONEncoder().encode(original)

        // Decode it back from JSON (simulating loading from a file)
        let decoded = try JSONDecoder().decode(WritingInstrumentSettings.self, from: data)

        // The decoded settings should be identical to the original
        #expect(decoded == original)
    }

    // MARK: - Equatable
    // Tests for comparing two settings objects

    @Test func equatable_sameValues_areEqual() {
        // Two pens with the same settings should be equal
        let a = WritingInstrumentSettings.pen()
        let b = WritingInstrumentSettings.pen()
        #expect(a == b)
    }

    @Test func equatable_differentValues_areNotEqual() {
        // A pen and an eraser have different settings, so they shouldn't be equal
        let a = WritingInstrumentSettings.pen()
        let b = WritingInstrumentSettings.eraser()
        #expect(a != b)
    }
}
