import SwiftUI
import PencilKit

struct DrawingToolbar: View {
    @Binding var toolbarIcons: [ToolbarIcon]
    @Binding var selectedColor: Color
    @Binding var activeTool: ActiveTool
    var onImageRequested: () -> Void
    var undoManager: UndoManager?
    @Environment(\.colorScheme) private var colorScheme

    @State private var showColorPicker = false
    @State private var editingIconID: UUID?

    // Drag-to-delete state
    @State private var draggedIconID: UUID?
    @State private var dragOffset: CGSize = .zero
    @State private var isOutOfBounds = false
    @State private var lastDeletedColor: Color = .blue

    // Computed filtered lists
    private var toolIcons: [ToolbarIcon] {
        toolbarIcons.filter { $0.type != .color }
    }

    private var colorIcons: [ToolbarIcon] {
        toolbarIcons.filter { $0.type == .color }
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

            // Tool zone: pen, eraser, highlighter, lasso, text from toolbarIcons
            ForEach(toolIcons) { icon in
                iconButton(for: icon)
                    .opacity(draggedIconID == icon.id ? 0.3 : 1.0)
            }

            Divider().frame(width: 28)

            // Color zone
            ForEach(colorIcons) { icon in
                iconButton(for: icon)
                    .opacity(draggedIconID == icon.id ? 0.3 : 1.0)
            }

            // Plus button
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
                    activeTool: $activeTool,
                    defaultColor: lastDeletedColor,
                    onImageRequested: onImageRequested
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
        Group {
            if icon.type == .color, let color = icon.color {
                colorIconView(icon: icon, color: color)
            } else {
                toolIconView(icon: icon)
            }
        }
        .scaleEffect(draggedIconID == icon.id ? (isOutOfBounds ? 0.8 : 1.0) : 1.0)
        .offset(draggedIconID == icon.id ? dragOffset : .zero)
        .popover(isPresented: Binding(
            get: { editingIconID == icon.id },
            set: { if !$0 { editingIconID = nil } }
        )) {
            popoverContent(for: icon)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if value.translation.width != 0 || value.translation.height != 0 {
                        draggedIconID = icon.id
                        dragOffset = value.translation

                        let distance = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))

                        let canDelete: Bool = {
                            if !icon.isEssential {
                                return true
                            } else {
                                let countOfType = toolbarIcons.filter { $0.type == icon.type }.count
                                return countOfType > 1
                            }
                        }()

                        if distance > 45 && !isOutOfBounds && canDelete {
                            isOutOfBounds = true

                            if icon.type == .color, let deletedColor = icon.color {
                                lastDeletedColor = deletedColor
                            }

                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                toolbarIcons.removeAll { $0.id == icon.id }
                            }
                        }
                    }
                }
                .onEnded { value in
                    let distance = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))

                    if distance < 5 {
                        handleIconTap(icon)
                    }

                    withAnimation(.spring(response: 0.3)) {
                        draggedIconID = nil
                        dragOffset = .zero
                        isOutOfBounds = false
                    }
                }
        )
    }

    // MARK: - Color Icon
    private func colorIconView(icon: ToolbarIcon, color: Color) -> some View {
        let isDrawingTool = activeTool == .pen || activeTool == .highlighter
        return Circle()
            .fill(color)
            .frame(width: 24, height: 24)
            .overlay {
                if isDrawingTool && selectedColor.isSimilar(to: color, colorScheme: colorScheme) {
                    Image(systemName: "checkmark")
                        .font(.caption2.bold())
                        .foregroundStyle(color.isLight(colorScheme: colorScheme) ? .black : .white)
                }
            }
            .overlay {
                Circle().stroke(Color.primary.opacity(0.3), lineWidth: 1)
            }
    }

    // MARK: - Tool Icon
    private func toolIconView(icon: ToolbarIcon) -> some View {
        let isActive = activeToolMatches(icon.type)
        return Image(systemName: icon.type.iconName)
            .font(.system(size: 14))
            .fontWeight(isActive ? .bold : .regular)
            .frame(width: 24, height: 24)
            .foregroundStyle(toolForeground(for: icon.type, isActive: isActive))
    }

    private func toolForeground(for type: ToolType, isActive: Bool) -> some ShapeStyle {
        if !isActive { return AnyShapeStyle(.secondary) }
        switch type {
        case .pencil, .highlighter:
            return AnyShapeStyle(selectedColor)
        default:
            return AnyShapeStyle(.primary)
        }
    }

    private func activeToolMatches(_ type: ToolType) -> Bool {
        switch type {
        case .pencil: return activeTool == .pen
        case .eraser: return activeTool == .eraser
        case .highlighter: return activeTool == .highlighter
        case .lasso: return activeTool == .lasso
        case .text: return activeTool == .text
        default: return false
        }
    }

    private func activeToolFor(_ type: ToolType) -> ActiveTool {
        switch type {
        case .pencil: return .pen
        case .eraser: return .eraser
        case .highlighter: return .highlighter
        case .lasso: return .lasso
        case .text: return .text
        default: return .pen
        }
    }

    // MARK: - Popover Content
    @ViewBuilder
    private func popoverContent(for icon: ToolbarIcon) -> some View {
        if icon.type == .color {
            EditColorView(
                toolbarIcons: $toolbarIcons,
                icon: icon,
                selectedColor: $selectedColor
            )
        } else if icon.type.isWritingInstrument,
                  let idx = toolbarIcons.firstIndex(where: { $0.id == icon.id }) {
            let range = sliderRange(for: icon.type)
            let opacity: Double = icon.type == .highlighter ? 0.4 : 1.0
            let color = icon.type == .eraser ? Color.primary : selectedColor
            InstrumentPopoverView(
                settings: $toolbarIcons[idx].instrumentSettings ?? .constant(.pen()),
                sliderRange: range,
                displayColor: color,
                colorOpacity: opacity
            )
        }
    }

    private func sliderRange(for type: ToolType) -> ClosedRange<CGFloat> {
        switch type {
        case .pencil: return 1...50
        case .eraser: return 10...150
        case .highlighter: return 5...40
        default: return 1...50
        }
    }

    // MARK: - Icon Tap Handler
    private func handleIconTap(_ icon: ToolbarIcon) {
        switch icon.type {
        case .color:
            if let color = icon.color {
                if (activeTool == .pen || activeTool == .highlighter) && selectedColor.isSimilar(to: color, colorScheme: colorScheme) {
                    editingIconID = icon.id
                } else {
                    selectedColor = color
                    if activeTool == .eraser || activeTool == .lasso || activeTool == .text {
                        activeTool = .pen
                    }
                }
            }
        case .pencil, .eraser, .highlighter:
            let targetTool = activeToolFor(icon.type)
            if activeTool == targetTool {
                editingIconID = icon.id // show instrument popover
            } else {
                activeTool = targetTool
            }
        case .lasso:
            activeTool = .lasso
        case .text:
            activeTool = .text
        default:
            break
        }
    }
}

// MARK: - Binding helper for optional instrumentSettings
private extension Binding where Value == WritingInstrumentSettings? {
    static func ?? (lhs: Binding<WritingInstrumentSettings?>, rhs: Binding<WritingInstrumentSettings>) -> Binding<WritingInstrumentSettings> {
        Binding<WritingInstrumentSettings>(
            get: { lhs.wrappedValue ?? rhs.wrappedValue },
            set: { lhs.wrappedValue = $0 }
        )
    }
}
