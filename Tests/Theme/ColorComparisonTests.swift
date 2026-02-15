import Testing
import SwiftUI
@testable import SupaNotes

struct ColorComparisonTests {

    // MARK: - resolveRGB

    @Test func resolveRGB_white_returnsNearOne() {
        let (r, g, b) = Color.white.resolveRGB(colorScheme: .light)
        #expect(r > 0.99)
        #expect(g > 0.99)
        #expect(b > 0.99)
    }

    @Test func resolveRGB_black_returnsNearZero() {
        let (r, g, b) = Color.black.resolveRGB(colorScheme: .light)
        #expect(r < 0.01)
        #expect(g < 0.01)
        #expect(b < 0.01)
    }

    @Test func resolveRGB_red_hasHighRedComponent() {
        let (r, g, b) = Color.red.resolveRGB(colorScheme: .light)
        #expect(r > 0.9)
        #expect(g < 0.3)
        #expect(b < 0.3)
    }

    // MARK: - isLight

    @Test func isLight_white_returnsTrue() {
        #expect(Color.white.isLight(colorScheme: .light) == true)
    }

    @Test func isLight_black_returnsFalse() {
        #expect(Color.black.isLight(colorScheme: .light) == false)
    }

    @Test func isLight_yellow_returnsTrue() {
        #expect(Color.yellow.isLight(colorScheme: .light) == true)
    }

    @Test func isLight_darkBlue_returnsFalse() {
        let darkBlue = Color(red: 0.0, green: 0.0, blue: 0.3)
        #expect(darkBlue.isLight(colorScheme: .light) == false)
    }

    // MARK: - isSimilar

    @Test func isSimilar_identicalColors_returnsTrue() {
        let color = Color(red: 0.5, green: 0.3, blue: 0.7)
        #expect(color.isSimilar(to: color, colorScheme: .light) == true)
    }

    @Test func isSimilar_nearIdenticalColors_returnsTrue() {
        let c1 = Color(red: 0.5, green: 0.3, blue: 0.7)
        let c2 = Color(red: 0.509, green: 0.309, blue: 0.709)
        #expect(c1.isSimilar(to: c2, colorScheme: .light) == true)
    }

    @Test func isSimilar_clearlyDifferentColors_returnsFalse() {
        #expect(Color.red.isSimilar(to: Color.blue, colorScheme: .light) == false)
    }

    @Test func isSimilar_blackAndWhite_returnsFalse() {
        #expect(Color.black.isSimilar(to: Color.white, colorScheme: .light) == false)
    }
}
