import SwiftUI
import PencilKit

struct DrawingToolbar: View {
    @Binding var toolbarIcons: [ToolbarIcon]
    @Binding var selectedColor: Color
    @Binding var activeTool: ActiveTool
    var undoManager: UndoManager?
    @Environment(\.colorScheme) private var colorScheme

    @State private var showColorPicker = false
    @State private var editingIconID: UUID?

    // Drag state
    @State private var draggedIconID: UUID?
    @State private var dragTranslation: CGSize = .zero
    @State private var isDraggingOutOfBounds = false
    @State private var lastDeletedColor: Color = .blue

    // Reorder state
    @State private var dragStartZoneIndex: Int?
    @State private var currentZoneIndex: Int?
    @State private var dragZoneIsColor: Bool = false

    // MARK: - Axis abstraction
    private var toolbarAxis: Axis { .vertical }

    private let slotPitch: CGFloat = 36 // 24pt icon + 12pt spacing

    private func mainAxisValue(_ size: CGSize) -> CGFloat {
        toolbarAxis == .vertical ? size.height : size.width
    }

    private func crossAxisValue(_ size: CGSize) -> CGFloat {
        toolbarAxis == .vertical ? size.width : size.height
    }

    private func mainAxisOffset(_ value: CGFloat) -> CGSize {
        toolbarAxis == .vertical ? CGSize(width: 0, height: value) : CGSize(width: value, height: 0)
    }

    /// The offset applied to the dragged icon so it stays glued to the finger
    /// even as the array reorders underneath it.
    private var residualOffset: CGSize {
        guard let start = dragStartZoneIndex, let current = currentZoneIndex else {
            return dragTranslation
        }
        let mainShift = mainAxisValue(dragTranslation) - CGFloat(current - start) * slotPitch
        let crossShift = crossAxisValue(dragTranslation)
        if toolbarAxis == .vertical {
            return CGSize(width: crossShift, height: mainShift)
        } else {
            return CGSize(width: mainShift, height: crossShift)
        }
    }

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

            // Tool zone
            ForEach(toolIcons) { icon in
                iconButton(for: icon)
            }

            Divider().frame(width: 28)

            // Color zone
            ForEach(colorIcons) { icon in
                iconButton(for: icon)
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

    // MARK: - Icon Button with Drag-to-Reorder/Delete
    private func iconButton(for icon: ToolbarIcon) -> some View {
        let isDragged = draggedIconID == icon.id
        return Group {
            if icon.type == .color, let color = icon.color {
                colorIconView(icon: icon, color: color)
            } else {
                toolIconView(icon: icon)
            }
        }
        .scaleEffect(isDragged ? (isDraggingOutOfBounds ? 0.8 : 1.05) : 1.0)
        .shadow(color: isDragged && !isDraggingOutOfBounds ? .black.opacity(0.2) : .clear, radius: 4, x: 0, y: 2)
        .offset(isDragged ? residualOffset : .zero)
        .zIndex(isDragged ? 100 : 0)
        .popover(isPresented: Binding(
            get: { editingIconID == icon.id },
            set: { if !$0 { editingIconID = nil } }
        )) {
            popoverContent(for: icon)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let translation = value.translation
                    guard abs(translation.width) > 2 || abs(translation.height) > 2 else { return }

                    // Initialize drag on first significant movement
                    if draggedIconID != icon.id {
                        draggedIconID = icon.id
                        let isColor = icon.type == .color
                        dragZoneIsColor = isColor
                        let zone = isColor ? colorIcons : toolIcons
                        let zoneIdx = zone.firstIndex(where: { $0.id == icon.id }) ?? 0
                        dragStartZoneIndex = zoneIdx
                        currentZoneIndex = zoneIdx
                    }

                    dragTranslation = translation

                    let crossAxis = abs(crossAxisValue(translation))
                    let canDelete: Bool = {
                        if !icon.isEssential { return true }
                        return toolbarIcons.filter { $0.type == icon.type }.count > 1
                    }()

                    // Cross-axis deletion
                    if crossAxis > 50 && !isDraggingOutOfBounds && canDelete {
                        isDraggingOutOfBounds = true
                        if icon.type == .color, let deletedColor = icon.color {
                            lastDeletedColor = deletedColor
                        }
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            toolbarIcons.removeAll { $0.id == icon.id }
                        }
                        return
                    }

                    // Main-axis reorder
                    guard !isDraggingOutOfBounds, let startIdx = dragStartZoneIndex, let curIdx = currentZoneIndex else { return }
                    let mainDelta = mainAxisValue(translation)
                    let targetIdx = max(0, startIdx + Int(round(mainDelta / slotPitch)))
                    let zone = dragZoneIsColor ? colorIcons : toolIcons
                    let clampedTarget = min(targetIdx, zone.count - 1)

                    if clampedTarget != curIdx {
                        moveIconInZone(id: icon.id, toZoneIndex: clampedTarget, isColor: dragZoneIsColor)
                        currentZoneIndex = clampedTarget
                    }
                }
                .onEnded { value in
                    let distance = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))
                    if distance < 5 {
                        handleIconTap(icon)
                    }

                    withAnimation(.spring(response: 0.3)) {
                        draggedIconID = nil
                        dragTranslation = .zero
                        isDraggingOutOfBounds = false
                        dragStartZoneIndex = nil
                        currentZoneIndex = nil
                    }
                }
        )
    }

    // MARK: - Reorder Helper
    /// Moves an icon to a target zone-local index within its zone (tools or colors).
    private func moveIconInZone(id: UUID, toZoneIndex target: Int, isColor: Bool) {
        guard let currentFlatIndex = toolbarIcons.firstIndex(where: { $0.id == id }) else { return }

        // Build list of flat indices for this zone
        let zoneIndices = toolbarIcons.indices.filter { isColor ? toolbarIcons[$0].type == .color : toolbarIcons[$0].type != .color }
        let clampedTarget = min(max(target, 0), zoneIndices.count - 1)
        let targetFlatIndex = zoneIndices[clampedTarget]

        guard currentFlatIndex != targetFlatIndex else { return }

        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            let icon = toolbarIcons.remove(at: currentFlatIndex)
            // After removal, recalculate zone indices
            let newZoneIndices = toolbarIcons.indices.filter { isColor ? toolbarIcons[$0].type == .color : toolbarIcons[$0].type != .color }
            let insertAt: Int
            if clampedTarget >= newZoneIndices.count {
                // Insert after the last item in zone
                insertAt = (newZoneIndices.last ?? toolbarIcons.count - 1) + 1
            } else {
                insertAt = newZoneIndices[clampedTarget]
            }
            toolbarIcons.insert(icon, at: insertAt)
        }
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
        default: return false
        }
    }

    private func activeToolFor(_ type: ToolType) -> ActiveTool {
        switch type {
        case .pencil: return .pen
        case .eraser: return .eraser
        case .highlighter: return .highlighter
        case .lasso: return .lasso
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
                    if activeTool == .eraser || activeTool == .lasso {
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
