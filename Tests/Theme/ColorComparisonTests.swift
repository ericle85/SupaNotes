import Testing
import SwiftUI
@testable import SupaNotes

/// Tests for color comparison functions
/// These tests verify that we can correctly convert colors to RGB values,
/// determine if a color is light or dark, and check if two colors are similar.
struct ColorComparisonTests {

    // MARK: - resolveRGB
    // This section tests converting a SwiftUI Color to its red, green, blue components
    // Each component is a value from 0.0 (none) to 1.0 (full)

    @Test func resolveRGB_white_returnsNearOne() {
        // White should have high values for all three RGB components
        let (r, g, b) = Color.white.resolveRGB(colorScheme: .light)
        #expect(r > 0.99)  // Red component is almost 1.0
        #expect(g > 0.99)  // Green component is almost 1.0
        #expect(b > 0.99)  // Blue component is almost 1.0
    }

    @Test func resolveRGB_black_returnsNearZero() {
        // Black should have low values for all three RGB components
        let (r, g, b) = Color.black.resolveRGB(colorScheme: .light)
        #expect(r < 0.01)  // Red component is almost 0.0
        #expect(g < 0.01)  // Green component is almost 0.0
        #expect(b < 0.01)  // Blue component is almost 0.0
    }

    @Test func resolveRGB_red_hasHighRedComponent() {
        // Red color should have a high red component, but low green and blue
        let (r, g, b) = Color.red.resolveRGB(colorScheme: .light)
        #expect(r > 0.9)   // Red component is high
        #expect(g < 0.3)   // Green component is low
        #expect(b < 0.3)   // Blue component is low
    }

    // MARK: - isLight
    // This section tests a function that determines if a color appears light or dark

    @Test func isLight_white_returnsTrue() {
        // White is definitely a light color
        #expect(Color.white.isLight(colorScheme: .light) == true)
    }

    @Test func isLight_black_returnsFalse() {
        // Black is definitely a dark color
        #expect(Color.black.isLight(colorScheme: .light) == false)
    }

    @Test func isLight_yellow_returnsTrue() {
        // Yellow is a light color (brightish)
        #expect(Color.yellow.isLight(colorScheme: .light) == true)
    }

    @Test func isLight_darkBlue_returnsFalse() {
        // A custom dark blue should be detected as a dark color
        let darkBlue = Color(red: 0.0, green: 0.0, blue: 0.3)
        #expect(darkBlue.isLight(colorScheme: .light) == false)
    }

    // MARK: - isSimilar
    // This section tests a function that checks if two colors are close enough to be considered the same

    @Test func isSimilar_identicalColors_returnsTrue() {
        // A color compared to itself should always be similar
        let color = Color(red: 0.5, green: 0.3, blue: 0.7)
        #expect(color.isSimilar(to: color, colorScheme: .light) == true)
    }

    @Test func isSimilar_nearIdenticalColors_returnsTrue() {
        // Two colors that are almost the same (differ by about 0.009) should be considered similar
        let c1 = Color(red: 0.5, green: 0.3, blue: 0.7)
        let c2 = Color(red: 0.509, green: 0.309, blue: 0.709)  // Slightly different
        #expect(c1.isSimilar(to: c2, colorScheme: .light) == true)
    }

    @Test func isSimilar_clearlyDifferentColors_returnsFalse() {
        // Red and blue are completely different colors
        #expect(Color.red.isSimilar(to: Color.blue, colorScheme: .light) == false)
    }

    @Test func isSimilar_blackAndWhite_returnsFalse() {
        // Black and white are opposites - definitely not similar
        #expect(Color.black.isSimilar(to: Color.white, colorScheme: .light) == false)
    }
}
