import SwiftUI

/// A Codable wrapper for SwiftUI Color
/// Stores RGB values resolved for a specific color scheme
struct CodableColor: Codable, Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let opacity: Double

    /// Create from a SwiftUI Color
    init(color: Color, colorScheme: ColorScheme) {
        let (r, g, b) = color.resolveRGB(colorScheme: colorScheme)
        red = Double(r)
        green = Double(g)
        blue = Double(b)
        opacity = 1.0
    }

    /// Convert back to SwiftUI Color
    func toColor() -> Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }
}
