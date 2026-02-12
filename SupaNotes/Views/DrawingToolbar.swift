import SwiftUI
import UIKit
import PencilKit
import UniformTypeIdentifiers

// MARK: - Color Extension for Comparison
extension Color {
    func isLight(in environment: EnvironmentValues) -> Bool {
        let resolved = self.resolve(in: environment)
        let luminance = 0.299 * Double(resolved.red) + 0.587 * Double(resolved.green) + 0.114 * Double(resolved.blue)
        return luminance > 0.6
    }

    func isSimilar(to other: Color) -> Bool {
        #if os(iOS)
        let uiColor1 = UIColor(self)
        let uiColor2 = UIColor(other)

        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0

        // getRed can fail if color isn't in RGB color space
        guard uiColor1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
              uiColor2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else {
            // Fallback: convert to RGB color space first
            guard let rgb1 = uiColor1.cgColor.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil),
                  let rgb2 = uiColor2.cgColor.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil),
                  let components1 = rgb1.components,
                  let components2 = rgb2.components,
                  components1.count >= 3,
                  components2.count >= 3 else {
                return false
            }

            let threshold: CGFloat = 0.02  // Increased threshold
            return abs(components1[0] - components2[0]) < threshold &&
                   abs(components1[1] - components2[1]) < threshold &&
                   abs(components1[2] - components2[2]) < threshold
        }

        let threshold: CGFloat = 0.02  // Increased threshold to catch visually similar colors
        return abs(r1 - r2) < threshold &&
               abs(g1 - g2) < threshold &&
               abs(b1 - b2) < threshold
        #else
        return false
        #endif
    }
}

// MARK: - Tool Type Enum
enum ToolType: String, Codable, CaseIterable {
    case color
    case pencil
    case eraser
    case lasso
    case image
    case text

    var iconName: String {
        switch self {
        case .color: return "paintpalette.fill"
        case .pencil: return "pencil.tip"
        case .eraser: return "eraser.fill"
        case .lasso: return "lasso"
        case .image: return "photo"
        case .text: return "textformat"
        }
    }

    var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - Toolbar Icon Model (Generic for all tools)
struct ToolbarIcon: Identifiable, Equatable {
    let id = UUID()
    let type: ToolType

    // Type-specific properties
    var color: Color?       // For color tools
    var size: CGFloat?      // For pencil/eraser size
    var name: String

    // Essential tool types (must always have at least 1 of each)
    static let essentialTypes: Set<ToolType> = [.color, .pencil, .eraser]

    // Check if this icon's type is essential
    var isEssential: Bool {
        Self.essentialTypes.contains(type)
    }

    // Helper to create a color icon
    static func colorIcon(_ color: Color, name: String = "Color") -> ToolbarIcon {
        ToolbarIcon(type: .color, color: color, name: name)
    }

    // Helper to create a tool icon
    static func toolIcon(_ type: ToolType, name: String? = nil) -> ToolbarIcon {
        ToolbarIcon(type: type, name: name ?? type.displayName)
    }
}

struct DrawingToolbar: View {
    @Binding var selectedColor: Color
    @Binding var penWidth: CGFloat
    @Binding var eraserWidth: CGFloat
    @Binding var isErasing: Bool
    var undoManager: UndoManager?
    @Environment(\.self) private var environment

    @State private var showColorPicker = false
    @State private var showPenSlider = false
    @State private var showEraserSlider = false
    @State private var editingColorID: UUID?  // Track which color is being edited

    @State private var toolbarIcons: [ToolbarIcon] = [
          .colorIcon(.primary, name: "Black"),
          .colorIcon(.red, name: "Red"),
          .colorIcon(.blue, name: "Blue"),
          .colorIcon(.green, name: "Green"),
      ]

    // Drag-to-delete state
    @State private var draggedIconID: UUID?
    @State private var dragOffset: CGSize = .zero
    @State private var isOutOfBounds = false
    @State private var lastDeletedColor: Color = .blue

    var currentTool: PKTool {
        if isErasing {
            return PKEraserTool(.bitmap, width: eraserWidth)
        } else {
            return PKInkingTool(.pen, color: UIColor(selectedColor), width: penWidth)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Undo / Redo
            Button { undoManager?.undo() } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            Button { undoManager?.redo() } label: {
                Image(systemName: "arrow.uturn.forward")
            }

            Divider().frame(width: 28)

            // Pen
            Button {
                if !isErasing {
                    showPenSlider.toggle()
                } else {
                    isErasing = false
                }
                showEraserSlider = false
            } label: {
                Image(systemName: "pencil.tip")
                    .fontWeight(!isErasing ? .bold : .regular)
            }
            .foregroundStyle(!isErasing ? selectedColor : .secondary)
            .popover(isPresented: $showPenSlider, arrowEdge: .trailing) {
                VStack(spacing: 16) {
                    Circle()
                        .fill(selectedColor)
                        .frame(width: max(penWidth, 6), height: max(penWidth, 6))
                        .frame(width: 50, height: 50)

                    Slider(value: $penWidth, in: 1...50)
                        .frame(width: 200)

                    Text("\(Int(penWidth)) pt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .presentationCompactAdaptation(.popover)
            }

            // Eraser
            Button {
                if isErasing {
                    showEraserSlider.toggle()
                } else {
                    isErasing = true
                }
                showPenSlider = false
            } label: {
                Image(systemName: "eraser.fill")
                    .fontWeight(isErasing ? .bold : .regular)
            }
            .foregroundStyle(isErasing ? .primary : .secondary)
            .popover(isPresented: $showEraserSlider, arrowEdge: .trailing) {
                VStack(spacing: 16) {
                    Circle()
                        .fill(Color.primary)
                        .frame(width: max(eraserWidth * 0.5, 6), height: max(eraserWidth * 0.5, 6))
                        .frame(width: 50, height: 50)

                    Slider(value: $eraserWidth, in: 10...150)
                        .frame(width: 200)

                    Text("\(Int(eraserWidth)) pt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .presentationCompactAdaptation(.popover)
            }

            Divider().frame(width: 28)

            // Toolbar icons (colors and tools)
            ForEach(toolbarIcons) { icon in
                iconButton(for: icon)
                    .opacity(draggedIconID == icon.id ? 0.3 : 1.0)
            }

            // Plus button - hub to add new tools
            Button {
                showColorPicker = true
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 24, height: 24)

                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.primary)
                }
                .overlay {
                    Circle().stroke(Color.primary.opacity(0.3), lineWidth: 1)
                }
            }
            .popover(isPresented: $showColorPicker) {
                AddToolMenuView(
                    toolbarIcons: $toolbarIcons,
                    selectedColor: $selectedColor,
                    isErasing: $isErasing,
                    defaultColor: lastDeletedColor
                )
            }
        }
        .font(.title3)
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
        }
    }

    // MARK: - Icon Button with Drag-to-Delete
    private func iconButton(for icon: ToolbarIcon) -> some View {
        // Render based on tool type
        Group {
            if icon.type == .color, let color = icon.color {
                // Color circle
                Circle()
                    .fill(color)
                    .frame(width: 24, height: 24)
                    .overlay {
                        if selectedColor == color && !isErasing {
                            Image(systemName: "checkmark")
                                .font(.caption2.bold())
                                .foregroundStyle(color.isLight(in: environment) ? .black : .white)
                        }
                    }
                    .overlay {
                        Circle().stroke(Color.primary.opacity(0.3), lineWidth: 1)
                    }
            } else {
                // Other tool types (future: lasso, image, etc.)
                Image(systemName: icon.type.iconName)
                    .font(.system(size: 14))
                    .frame(width: 24, height: 24)
            }
        }
        // Visual feedback: fade out when being dragged
//        .opacity(draggedIconID == icon.id ? (isOutOfBounds ? 0.2 : 0.7) : 1.0)
        .scaleEffect(draggedIconID == icon.id ? (isOutOfBounds ? 0.8 : 1.0) : 1.0)
        .offset(draggedIconID == icon.id ? dragOffset : .zero)
        .popover(isPresented: Binding(
            get: { editingColorID == icon.id },
            set: { if !$0 { editingColorID = nil } }
        )) {
            if icon.type == .color {
                EditColorView(
                    toolbarIcons: $toolbarIcons,
                    icon: icon,
                    selectedColor: $selectedColor
                )
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    // Track dragging
                    if value.translation.width != 0 || value.translation.height != 0 {
                        draggedIconID = icon.id
                        dragOffset = value.translation

                        // Check if out of bounds (60px threshold)
                        let distance = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))

                        // Check if we can delete this icon
                        let canDelete: Bool = {
                            if !icon.isEssential {
                                return true  // Non-essential tools can always be deleted
                            } else {
                                // For essential tools, check if there's at least one other of the same type
                                let countOfType = toolbarIcons.filter { $0.type == icon.type }.count
                                return countOfType > 1
                            }
                        }()

                        // Auto-delete when dragged far enough
                        if distance > 45 && !isOutOfBounds && canDelete {
                            isOutOfBounds = true

                            // Save the color if it's a color icon (for quick re-add)
                            if icon.type == .color, let deletedColor = icon.color {
                                lastDeletedColor = deletedColor
                            }

                            // Remove from array - others will auto-slide in
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                toolbarIcons.removeAll { $0.id == icon.id }
                            }
                        }
                    }
                }
                .onEnded { value in
                    let distance = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))

                    if distance < 5 {
                        // Just a tap - select the tool or edit if already selected
                        if icon.type == .color, let color = icon.color {
                            if selectedColor == color && !isErasing {
                                // Already selected - open color picker to edit
                                editingColorID = icon.id
                            } else {
                                // Not selected - select it
                                selectedColor = color
                                isErasing = false
                            }
                        }
                        // Future: handle other tool types
                    }

                    // Reset drag state
                    withAnimation(.spring(response: 0.3)) {
                        draggedIconID = nil
                        dragOffset = .zero
                        isOutOfBounds = false
                    }
                }
        )
    }
}

// MARK: - Add Tool Menu View
struct AddToolMenuView: View {
    @Binding var toolbarIcons: [ToolbarIcon]
    @Binding var selectedColor: Color
    @Binding var isErasing: Bool
    let defaultColor: Color
    @Environment(\.dismiss) var dismiss

    @State private var newColor: Color = .blue

    init(toolbarIcons: Binding<[ToolbarIcon]>, selectedColor: Binding<Color>, isErasing: Binding<Bool>, defaultColor: Color) {
        _toolbarIcons = toolbarIcons
        _selectedColor = selectedColor
        _isErasing = isErasing
        self.defaultColor = defaultColor
        _newColor = State(initialValue: defaultColor)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Tool")
                .font(.headline)

            Divider()

            // Color option
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "paintpalette.fill")
                        .foregroundStyle(.blue)
                    Text("Color")
                        .font(.subheadline)
                    Spacer()
                }

                ColorPicker("Choose Color", selection: $newColor, supportsOpacity: false)

                Button("Add Color") {
                    // Check if this color already exists in the toolbar
                    if let existing = toolbarIcons.first(where: { $0.type == .color && $0.color?.isSimilar(to: newColor) == true }) {
                        // Just select the existing one
                        selectedColor = existing.color ?? newColor
                    } else {
                        let newIcon = ToolbarIcon.colorIcon(newColor, name: "Custom")
                        withAnimation(.spring(response: 0.3)) {
                            toolbarIcons.append(newIcon)
                        }
                        selectedColor = newColor
                    }
                    isErasing = false
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.1))
            }

            // Future tools (coming soon)
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "lasso")
                        .foregroundStyle(.secondary)
                    Text("Lasso Tool")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Coming Soon")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                HStack {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                    Text("Image Tool")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Coming Soon")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding()
        }
        .padding(20)
        .frame(width: 280)
    }
}

// MARK: - Edit Color View
struct EditColorView: View {
    @Binding var toolbarIcons: [ToolbarIcon]
    let icon: ToolbarIcon
    @Binding var selectedColor: Color
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
        // Check if another icon already has this color
        if let existing = toolbarIcons.first(where: { $0.id != icon.id && $0.type == .color && $0.color?.isSimilar(to: newColor) == true }) {
            // Delete the icon being edited and select the existing one
            withAnimation(.spring(response: 0.3)) {
                toolbarIcons.removeAll { $0.id == icon.id }
            }
            selectedColor = existing.color ?? newColor
            dismiss()
        } else if let index = toolbarIcons.firstIndex(where: { $0.id == icon.id }) {
            toolbarIcons[index] = ToolbarIcon.colorIcon(newColor, name: icon.name)
            selectedColor = newColor
        }
    }
}
