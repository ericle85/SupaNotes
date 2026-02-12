import SwiftUI

// MARK: - Add Tool Menu View
struct AddToolMenuView: View {
    @Binding var toolbarIcons: [ToolbarIcon]
    @Binding var selectedColor: Color
    @Binding var activeTool: ActiveTool
    let defaultColor: Color
    var onImageRequested: () -> Void
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

                // Color
                Button {
                    showColorPage = true
                } label: {
                    HStack {
                        Image(systemName: "paintpalette.fill")
                            .foregroundStyle(.blue)
                            .frame(width: 24)
                        Text("Color")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }

                // Highlighter
                Button {
                    let candidate = ToolbarIcon.toolIcon(.highlighter)
                    if !toolbarIcons.contains(where: { $0.isEquivalent(to: candidate, colorScheme: colorScheme) }) {
                        withAnimation(.spring(response: 0.3)) {
                            toolbarIcons.append(candidate)
                        }
                    }
                    activeTool = .highlighter
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "highlighter")
                            .foregroundStyle(.orange)
                            .frame(width: 24)
                        Text("Highlighter")
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }

                // Lasso
                Button {
                    let candidate = ToolbarIcon.toolIcon(.lasso)
                    if !toolbarIcons.contains(where: { $0.isEquivalent(to: candidate, colorScheme: colorScheme) }) {
                        withAnimation(.spring(response: 0.3)) {
                            toolbarIcons.append(candidate)
                        }
                    }
                    activeTool = .lasso
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "lasso")
                            .foregroundStyle(.purple)
                            .frame(width: 24)
                        Text("Lasso")
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }

                // Image
                Button {
                    onImageRequested()
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "photo")
                            .foregroundStyle(.green)
                            .frame(width: 24)
                        Text("Image")
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }

                // Textbox — adds as toolbar icon
                Button {
                    let candidate = ToolbarIcon.toolIcon(.text)
                    if !toolbarIcons.contains(where: { $0.isEquivalent(to: candidate, colorScheme: colorScheme) }) {
                        withAnimation(.spring(response: 0.3)) {
                            toolbarIcons.append(candidate)
                        }
                    }
                    activeTool = .text
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "textformat")
                            .foregroundStyle(.teal)
                            .frame(width: 24)
                        Text("Textbox")
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .buttonStyle(.plain)
            .padding(16)
            .frame(width: 220)
            .presentationCompactAdaptation(.popover)
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

    private let presetColors: [Color] = [
        .white, .black, .red, .orange, .yellow, .green, .blue, .purple
    ]

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

            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 44), spacing: 12)
            ], spacing: 12) {
                ForEach(presetColors, id: \.self) { color in
                    Button {
                        addOrSelect(color)
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

            ColorPicker("Custom Color", selection: $newColor, supportsOpacity: false)

            Button("Add Color") {
                addOrSelect(newColor)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(width: 260)
        .presentationCompactAdaptation(.popover)
    }

    private func addOrSelect(_ color: Color) {
        let candidate = ToolbarIcon.colorIcon(color, colorScheme: colorScheme)
        if let existing = toolbarIcons.first(where: { $0.isEquivalent(to: candidate, colorScheme: colorScheme) }) {
            selectedColor = existing.color ?? color
        } else {
            let newIcon = ToolbarIcon.colorIcon(color, name: "Custom", colorScheme: colorScheme)
            withAnimation(.spring(response: 0.3)) {
                toolbarIcons.append(newIcon)
            }
            selectedColor = color
        }
        if activeTool == .eraser || activeTool == .lasso || activeTool == .text {
            activeTool = .pen
        }
        dismiss()
    }
}
