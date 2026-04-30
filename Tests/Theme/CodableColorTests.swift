import Testing
import SwiftUI
import Foundation
@testable import SupaNotes

/// Tests for CodableColor
/// CodableColor is a wrapper around SwiftUI's Color that can be saved to JSON
/// We need this because SwiftUI's Color can't be directly saved to files
@Suite struct CodableColorTests {

    @Test func roundTrip_preservesRGBValues() throws {
        // Create a color with specific RGB values
        let original = CodableColor(color: Color(red: 0.2, green: 0.4, blue: 0.8))

        // Encode to JSON (like saving to a file)
        let data = try JSONEncoder().encode(original)

        // Decode back from JSON (like loading from a file)
        let decoded = try JSONDecoder().decode(CodableColor.self, from: data)

        // The decoded values should match the original (allowing tiny rounding differences)
        #expect(abs(decoded.red - original.red) < 0.01)       // Red component preserved
        #expect(abs(decoded.green - original.green) < 0.01)   // Green component preserved
        #expect(abs(decoded.blue - original.blue) < 0.01)     // Blue component preserved
        #expect(abs(decoded.opacity - original.opacity) < 0.01) // Opacity preserved
    }

    @Test func initFromColor_capturesComponents() {
        // Create a CodableColor from white (which is full brightness for all channels)
        let codable = CodableColor(color: .white)

        // White should have high values for all components
        #expect(codable.red > 0.99)      // Red is almost 1.0
        #expect(codable.green > 0.99)    // Green is almost 1.0
        #expect(codable.blue > 0.99)     // Blue is almost 1.0
        #expect(abs(codable.opacity - 1.0) < 0.01)  // Fully opaque
    }

    @Test func toColor_producesEquivalentColor() {
        // Create a CodableColor with specific RGB values
        let codable = CodableColor(color: Color(red: 0.3, green: 0.6, blue: 0.9))

        // Convert it back to a SwiftUI Color
        let restored = codable.toColor()

        // Get the RGB components from the restored color
        let (r, g, b) = restored.resolveRGB(colorScheme: .light)

        // The restored color should have similar RGB values (allowing for tiny rounding errors)
        #expect(abs(Double(r) - codable.red) < 0.02)
        #expect(abs(Double(g) - codable.green) < 0.02)
        #expect(abs(Double(b) - codable.blue) < 0.02)
    }

    @Test func equality_sameValues_areEqual() {
        // Two CodableColors with the same red color should be equal
        let a = CodableColor(color: .red)
        let b = CodableColor(color: .red)
        #expect(a == b)
    }

    @Test func equality_differentValues_areNotEqual() {
        // Red and blue are different colors, so they shouldn't be equal
        let a = CodableColor(color: .red)
        let b = CodableColor(color: .blue)
        #expect(a != b)
    }
}
