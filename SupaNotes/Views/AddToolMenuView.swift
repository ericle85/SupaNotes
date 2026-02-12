import SwiftUI

// MARK: - Add Tool Menu View
struct AddToolMenuView: View {
    @Binding var toolbarIcons: [ToolbarIcon]
    @Binding var selectedColor: Color
    @Binding var isErasing: Bool
    let defaultColor: Color
    @Environment(\.dismiss) var dismiss

    @State private var showColorPage = false

    var body: some View {
        if showColorPage {
            AddColorView(
                toolbarIcons: $toolbarIcons,
                selectedColor: $selectedColor,
                isErasing: $isErasing,
                defaultColor: defaultColor,
                onBack: { showColorPage = false }
            )
        } else {
            VStack(spacing: 8) {
                Text("Add Tool")
                    .font(.headline)
                    .padding(.bottom, 4)

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

                Button {
                    // Future: add lasso tool
                } label: {
                    HStack {
                        Image(systemName: "lasso")
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                        Text("Lasso")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Coming Soon")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                }
                .disabled(true)

                Button {
                    // Future: add image tool
                } label: {
                    HStack {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                        Text("Image")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Coming Soon")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                }
                .disabled(true)
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
    @Binding var isErasing: Bool
    let defaultColor: Color
    var onBack: () -> Void
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var newColor: Color = .blue

    init(toolbarIcons: Binding<[ToolbarIcon]>, selectedColor: Binding<Color>, isErasing: Binding<Bool>, defaultColor: Color, onBack: @escaping () -> Void) {
        _toolbarIcons = toolbarIcons
        _selectedColor = selectedColor
        _isErasing = isErasing
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
                // Balance the back button
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
        let candidate = ToolbarIcon.colorIcon(color)
        if let existing = toolbarIcons.first(where: { $0.isEquivalent(to: candidate, colorScheme: colorScheme) }) {
            selectedColor = existing.color ?? color
        } else {
            let newIcon = ToolbarIcon.colorIcon(color, name: "Custom")
            withAnimation(.spring(response: 0.3)) {
                toolbarIcons.append(newIcon)
            }
            selectedColor = color
        }
        isErasing = false
        dismiss()
    }
}
