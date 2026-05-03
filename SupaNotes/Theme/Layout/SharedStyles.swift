import SwiftUI

// MARK: - Color Swatch View

struct ColorSwatchView: View {
    let color: Color
    var size: CGFloat = Design.Layout.colorSwatchSize
    var showCheckmark: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                if showCheckmark {
                    Image(systemName: "checkmark")
                        .font(.caption2.bold())
                        .foregroundStyle(color.isLight(colorScheme: colorScheme) ? .black : .white)
                }
            }
            .overlay {
                Circle().stroke(Color.primary.opacity(0.3), lineWidth: 1)
            }
    }
}

// MARK: - Floating Button Style

struct FloatingButtonStyle: ViewModifier {
    var size: CGFloat = Design.Layout.floatingButtonSize
    var cornerRadius: CGFloat = Design.CornerRadius.medium
    var shadow: Design.Shadow = .floating

    func body(content: Content) -> some View {
        content
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color("ToolbarBackground"))
                    .shadow(color: .black.opacity(shadow.opacity), radius: shadow.radius, x: shadow.x, y: shadow.y)
            )
    }
}

extension View {
    func floatingButton(
        size: CGFloat = Design.Layout.floatingButtonSize,
        cornerRadius: CGFloat = Design.CornerRadius.medium,
        shadow: Design.Shadow = .floating
    ) -> some View {
        modifier(FloatingButtonStyle(size: size, cornerRadius: cornerRadius, shadow: shadow))
    }
}

// MARK: - Binding Helper for Optional Values

extension Binding where Value == WritingInstrumentSettings? {
    static func ?? (lhs: Binding<WritingInstrumentSettings?>, rhs: Binding<WritingInstrumentSettings>) -> Binding<WritingInstrumentSettings> {
        Binding<WritingInstrumentSettings>(
            get: { lhs.wrappedValue ?? rhs.wrappedValue },
            set: { lhs.wrappedValue = $0 }
        )
    }
}
