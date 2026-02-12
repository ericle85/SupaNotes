import SwiftUI

// MARK: - Edit Color View
struct EditColorView: View {
    @Binding var toolbarIcons: [ToolbarIcon]
    let icon: ToolbarIcon
    @Binding var selectedColor: Color
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) var dismiss

    // Preset colors
    private let presetColors: [Color] = [
        .white, .black, .red, .orange, .yellow, .green, .blue, .purple
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text("Choose Color")
                .font(.headline)

            // Preset color buttons
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 44), spacing: 12)
            ], spacing: 12) {
                ForEach(presetColors, id: \.self) { color in
                    Button {
                        updateColor(to: color)
                        dismiss()
                    } label: {
                        Circle()
                            .fill(color)
                            .frame(width: 44, height: 44)
                            .overlay {
                                Circle()
                                    .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            // Custom color picker - updates live
            ColorPicker("Custom Color", selection: Binding(
                get: {
                    if let index = toolbarIcons.firstIndex(where: { $0.id == icon.id }),
                       let color = toolbarIcons[index].color {
                        return color
                    }
                    return .blue
                },
                set: { newColor in
                    updateColor(to: newColor)
                }
            ), supportsOpacity: false)
        }
        .padding(20)
        .frame(width: 260)
        .presentationCompactAdaptation(.popover)
    }

    private func updateColor(to newColor: Color) {
        let candidate = ToolbarIcon.colorIcon(newColor)
        if let existing = toolbarIcons.first(where: { $0.id != icon.id && $0.isEquivalent(to: candidate, colorScheme: colorScheme) }) {
            // Delete the icon being edited and select the existing one
            withAnimation(.spring(response: 0.3)) {
                toolbarIcons.removeAll { $0.id == icon.id }
            }
            selectedColor = existing.color ?? newColor
            dismiss()
        } else if let index = toolbarIcons.firstIndex(where: { $0.id == icon.id }) {
            // Mutate in place to preserve the icon's ID (keeps the popover open)
            toolbarIcons[index].color = newColor
            selectedColor = newColor
        }
    }
}
