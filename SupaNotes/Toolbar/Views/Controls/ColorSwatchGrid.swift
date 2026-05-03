import SwiftUI

/// A grid of colored circles the user can tap to pick a color.
/// Used in AddColorView (adding a new color to the toolbar) and EditColorView (changing an existing toolbar color).
/// The caller passes in the list of colors to show and a closure that runs when one is tapped.
struct ColorSwatchGrid: View {
    /// The colors to display as tappable circles.
    let colors: [Color]
    /// Called with the chosen color when the user taps a swatch.
    let onSelect: (Color) -> Void

    var body: some View {
        // LazyVGrid lays out items in a flexible grid — it adds as many columns as fit,
        // each at least colorSwatchLargeSize wide, with 12pt gaps between them.
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: Design.Layout.colorSwatchLargeSize), spacing: 12),
        ], spacing: 12) {
            ForEach(colors, id: \.self) { color in
                Button {
                    // Tell the parent which color was picked.
                    onSelect(color)
                } label: {
                    // Draw a filled circle in the swatch color.
                    Circle()
                        .fill(color)
                        .frame(width: Design.Layout.colorSwatchLargeSize, height: Design.Layout.colorSwatchLargeSize)
                        .overlay {
                            // Thin border so light colors (like white) are still visible against the background.
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                        }
                }
                // Plain style removes the default button highlight so the circle looks clean.
                .buttonStyle(.plain)
            }
        }
    }
}
