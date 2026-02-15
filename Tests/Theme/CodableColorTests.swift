import Testing
import SwiftUI
import Foundation
@testable import SupaNotes

struct CodableColorTests {

    @Test func roundTrip_preservesRGBValues() throws {
        let original = CodableColor(color: Color(red: 0.2, green: 0.4, blue: 0.8), colorScheme: .light)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CodableColor.self, from: data)

        #expect(abs(decoded.red - original.red) < 0.01)
        #expect(abs(decoded.green - original.green) < 0.01)
        #expect(abs(decoded.blue - original.blue) < 0.01)
        #expect(abs(decoded.opacity - original.opacity) < 0.01)
    }

    @Test func initFromColor_capturesComponents() {
        let codable = CodableColor(color: .white, colorScheme: .light)
        #expect(codable.red > 0.99)
        #expect(codable.green > 0.99)
        #expect(codable.blue > 0.99)
        #expect(abs(codable.opacity - 1.0) < 0.01)
    }

    @Test func toColor_producesEquivalentColor() {
        let codable = CodableColor(color: Color(red: 0.3, green: 0.6, blue: 0.9), colorScheme: .light)
        let restored = codable.toColor()
        let (r, g, b) = restored.resolveRGB(colorScheme: .light)

        #expect(abs(Double(r) - codable.red) < 0.02)
        #expect(abs(Double(g) - codable.green) < 0.02)
        #expect(abs(Double(b) - codable.blue) < 0.02)
    }

    @Test func equality_sameValues_areEqual() {
        let a = CodableColor(color: .red, colorScheme: .light)
        let b = CodableColor(color: .red, colorScheme: .light)
        #expect(a == b)
    }

    @Test func equality_differentValues_areNotEqual() {
        let a = CodableColor(color: .red, colorScheme: .light)
        let b = CodableColor(color: .blue, colorScheme: .light)
        #expect(a != b)
    }
}
