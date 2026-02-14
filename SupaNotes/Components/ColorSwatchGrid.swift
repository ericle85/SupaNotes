import SwiftUI

struct ColorSwatchGrid: View {
    let colors: [Color]
    let onSelect: (Color) -> Void

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: Design.Layout.colorSwatchLargeSize), spacing: 12)
        ], spacing: 12) {
            ForEach(colors, id: \.self) { color in
                Button {
                    onSelect(color)
                } label: {
                    Circle()
                        .fill(color)
                        .frame(width: Design.Layout.colorSwatchLargeSize, height: Design.Layout.colorSwatchLargeSize)
                        .overlay {
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
