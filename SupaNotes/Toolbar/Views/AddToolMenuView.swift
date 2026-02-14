import SwiftUI

struct AddToolMenuView: View {
    @Binding var toolbarIcons: [ToolbarIcon]
    @Binding var selectedColor: Color
    @Binding var activeTool: ActiveTool
    let defaultColor: Color
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var showColorPage = false

    var body: some View {
        if showColorPage {
            AddColorView(
                toolbarIcons: $toolbarIcons,
                selectedColor: $selectedColor,
                activeTool: $activeTool,
                defaultColor: defaultColor,
                onBack: { showColorPage = false }
            )
        } else {
            VStack(spacing: 8) {
                Text("Add Tool")
                    .font(.headline)
                    .padding(.bottom, 4)

                toolRow(icon: "paintpalette.fill", color: .blue, label: "Color", showChevron: true) {
                    showColorPage = true
                }

                toolRow(icon: "highlighter", color: .orange, label: "Highlighter") {
                    addToolIfNeeded(.highlighter)
                    activeTool = .highlighter
                    dismiss()
                }

                toolRow(icon: "lasso", color: .purple, label: "Lasso") {
                    addToolIfNeeded(.lasso)
                    activeTool = .lasso
                    dismiss()
                }
            }
            .buttonStyle(.plain)
            .padding(16)
            .frame(width: 220)
            .presentationCompactAdaptation(.popover)
        }
    }

    @ViewBuilder
    private func toolRow(icon: String, color: Color, label: String, showChevron: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: Design.Layout.sidebarIconWidth)
                Text(label)
                Spacer()
                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: Design.CornerRadius.small))
        }
    }

    private func addToolIfNeeded(_ type: ToolType) {
        let candidate = ToolbarIcon.toolIcon(type)
        if !toolbarIcons.contains(where: { $0.isEquivalent(to: candidate, colorScheme: colorScheme) }) {
            withAnimation(.spring(response: 0.3)) {
                toolbarIcons.appendToZone(candidate)
            }
        }
    }
}

// MARK: - Add Color View
struct AddColorView: View {
    @Binding var toolbarIcons: [ToolbarIcon]
    @Binding var selectedColor: Color
    @Binding var activeTool: ActiveTool
    let defaultColor: Color
    var onBack: () -> Void
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var newColor: Color = .blue

    init(toolbarIcons: Binding<[ToolbarIcon]>, selectedColor: Binding<Color>, activeTool: Binding<ActiveTool>, defaultColor: Color, onBack: @escaping () -> Void) {
        _toolbarIcons = toolbarIcons
        _selectedColor = selectedColor
        _activeTool = activeTool
        self.defaultColor = defaultColor
        self.onBack = onBack
        _newColor = State(initialValue: defaultColor)
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button { onBack() } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.bold())
                }
                Spacer()
                Text("Add Color")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.left")
                    .font(.body.bold())
                    .hidden()
            }

            ColorSwatchGrid(colors: ColorPresets.all) { color in
                addOrSelect(color)
            }

            Divider()

            ColorPicker("Custom Color", selection: $newColor, supportsOpacity: false)

            Button("Add Color") {
                addOrSelect(newColor)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(width: Design.Layout.sidebarWidth)
        .presentationCompactAdaptation(.popover)
    }

    private func addOrSelect(_ color: Color) {
        let candidate = ToolbarIcon.colorIcon(color, colorScheme: colorScheme)
        if let existing = toolbarIcons.first(where: { $0.isEquivalent(to: candidate, colorScheme: colorScheme) }) {
            selectedColor = existing.color ?? color
        } else {
            let newIcon = ToolbarIcon.colorIcon(color, name: "Custom", colorScheme: colorScheme)
            withAnimation(.spring(response: 0.3)) {
                toolbarIcons.appendToZone(newIcon)
            }
            selectedColor = color
        }
        if activeTool == .eraser || activeTool == .lasso {
            activeTool = .pen
        }
        dismiss()
    }
}
