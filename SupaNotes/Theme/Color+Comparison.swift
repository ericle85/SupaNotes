import SwiftUI
import UIKit

extension Color {
    func resolveRGB(colorScheme: ColorScheme) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        let tc = UITraitCollection(userInterfaceStyle: style)
        let resolved = UIColor(self).resolvedColor(with: tc)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
    }

    func isLight(colorScheme: ColorScheme) -> Bool {
        let c = resolveRGB(colorScheme: colorScheme)
        let luminance = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
        return luminance > 0.6
    }

    func isSimilar(to other: Color, colorScheme: ColorScheme) -> Bool {
        let c1 = self.resolveRGB(colorScheme: colorScheme)
        let c2 = other.resolveRGB(colorScheme: colorScheme)
        let threshold: CGFloat = 0.02
        return abs(c1.r - c2.r) < threshold &&
               abs(c1.g - c2.g) < threshold &&
               abs(c1.b - c2.b) < threshold
    }
}
