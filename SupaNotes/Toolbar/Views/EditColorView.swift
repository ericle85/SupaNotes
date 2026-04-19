import SwiftUI

struct EditColorView: View {
    @Binding var toolbarIcons: [ToolbarIcon]
    let icon: ToolbarIcon
    @Binding var colorSelectedByUser: Color
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Choose Color")
                .font(.headline)

            ColorSwatchGrid(colors: ColorPresets.all) { color in
                updateColor(to: color)
                dismiss()
            }

            Divider()

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
        .frame(width: Design.Layout.sidebarWidth)
        .presentationCompactAdaptation(.popover)
    }

    private func updateColor(to newColor: Color) {
        let candidate = ToolbarIcon.colorIcon(newColor, colorScheme: colorScheme)
        if let existing = toolbarIcons.first(where: { $0.id != icon.id && $0.isEquivalent(to: candidate, colorScheme: colorScheme) }) {
            withAnimation(.spring(response: 0.3)) {
                toolbarIcons.removeAll { $0.id == icon.id }
            }
            colorSelectedByUser = existing.color ?? newColor
            dismiss()
        } else if let index = toolbarIcons.firstIndex(where: { $0.id == icon.id }) {
            toolbarIcons[index].colorData = CodableColor(color: newColor, colorScheme: colorScheme)
            colorSelectedByUser = newColor
        }
    }
}
