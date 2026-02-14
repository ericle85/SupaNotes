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

    // Drag state for icons
    @State private var draggedIconID: UUID?
    @State private var dragTranslation: CGSize = .zero
    @State private var isDraggingOutOfBounds = false
    @State private var lastDeletedColor: Color = .blue

    // Undo/redo availability
    @State private var canUndo = false
    @State private var canRedo = false

    // Reorder state
    @State private var dragStartZoneIndex: Int?
    @State private var proposedZoneIndex: Int?
    @State private var dragZoneIsColor: Bool = false

    // 4-edge snapping
    @AppStorage("toolbarEdge") private var toolbarEdge: String = "bottom"

    // Toolbar repositioning drag
    @State private var toolbarDragOffset: CGSize = .zero
    @State private var isDraggingToolbar = false
    @State private var didRepositionToolbar = false

    private var edge: Edge {
        switch toolbarEdge {
        case "top": return .top
        case "left": return .leading
        case "right": return .trailing
        default: return .bottom
        }
    }

    private var toolbarAxis: Axis {
        edge == .top || edge == .bottom ? .horizontal : .vertical
    }

    private let slotPitch: CGFloat = ToolbarConstants.tapTargetSize + 2

    private func mainAxisValue(_ size: CGSize) -> CGFloat {
        toolbarAxis == .vertical ? size.height : size.width
    }

    private func crossAxisValue(_ size: CGSize) -> CGFloat {
        toolbarAxis == .vertical ? size.width : size.height
    }

    private func mainAxisOffset(_ value: CGFloat) -> CGSize {
        toolbarAxis == .vertical ? CGSize(width: 0, height: value) : CGSize(width: value, height: 0)
    }

    // Computed filtered lists
    private var toolIcons: [ToolbarIcon] {
        toolbarIcons.filter { $0.type != .color }
    }

    private var colorIcons: [ToolbarIcon] {
        toolbarIcons.filter { $0.type == .color }
    }

    private func reorderDisplacement(for icon: ToolbarIcon) -> CGFloat {
        guard let dragID = draggedIconID, dragID != icon.id,
              let startIdx = dragStartZoneIndex,
              let proposed = proposedZoneIndex,
              startIdx != proposed else { return 0 }

        let isColor = icon.type == .color
        guard isColor == dragZoneIsColor else { return 0 }

        let zone = isColor ? colorIcons : toolIcons
        guard let myIdx = zone.firstIndex(where: { $0.id == icon.id }) else { return 0 }

        if startIdx < proposed {
            if myIdx > startIdx && myIdx <= proposed { return -slotPitch }
        } else {
            if myIdx >= proposed && myIdx < startIdx { return slotPitch }
        }
        return 0
    }

    private var toolbarAlignment: Alignment {
        switch edge {
        case .top: return .top
        case .bottom: return .bottom
        case .leading: return .leading
        case .trailing: return .trailing
        }
    }

    var body: some View {
        toolbarContent
            .fixedSize()
            .simultaneousGesture(
                DragGesture(minimumDistance: 15, coordinateSpace: .global)
                    .onChanged { value in
                        guard draggedIconID == nil else { return }
                        isDraggingToolbar = true
                        didRepositionToolbar = true
                        toolbarDragOffset = value.translation
                    }
                    .onEnded { value in
                        guard isDraggingToolbar else { return }
                        isDraggingToolbar = false
                        toolbarDragOffset = .zero
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            didRepositionToolbar = false
                        }

                        let screenSize = UIScreen.main.bounds.size
                        let loc = value.location

                        let distTop = loc.y
                        let distBottom = screenSize.height - loc.y
                        let distLeft = loc.x
                        let distRight = screenSize.width - loc.x

                        let minDist = min(distTop, distBottom, distLeft, distRight)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            if minDist == distTop {
                                toolbarEdge = "top"
                            } else if minDist == distBottom {
                                toolbarEdge = "bottom"
                            } else if minDist == distLeft {
                                toolbarEdge = "left"
                            } else {
                                toolbarEdge = "right"
                            }
                        }
                    }
            )
            .offset(isDraggingToolbar ? toolbarDragOffset : .zero)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: toolbarAlignment)
            .padding(edge == .leading || edge == .trailing ? .horizontal : .vertical, 8)
    }

    @ViewBuilder
    private var toolbarContent: some View {
        let layout = toolbarAxis == .horizontal
            ? AnyLayout(HStackLayout(spacing: 2))
            : AnyLayout(VStackLayout(spacing: 2))

        layout {
            // Undo / Redo
            Button {
                guard !didRepositionToolbar else { return }
                undoManager?.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .frame(width: ToolbarConstants.tapTargetSize, height: ToolbarConstants.tapTargetSize)
                    .contentShape(Rectangle())
            }
            .disabled(!canUndo)
            .opacity(canUndo ? 1 : 0.3)
            Button {
                guard !didRepositionToolbar else { return }
                undoManager?.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .frame(width: ToolbarConstants.tapTargetSize, height: ToolbarConstants.tapTargetSize)
                    .contentShape(Rectangle())
            }
            .disabled(!canRedo)
            .opacity(canRedo ? 1 : 0.3)

            dividerView

            // Tool zone
            ForEach(toolIcons) { icon in
                iconButton(for: icon)
            }

            dividerView

            // Color zone
            ForEach(colorIcons) { icon in
                iconButton(for: icon)
            }

            // Plus button
            Button {
                guard !didRepositionToolbar else { return }
                showColorPicker = true
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 26, height: 26)
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                }
                .overlay {
                    Circle().stroke(Color.primary.opacity(0.3), lineWidth: 1)
                }
                .frame(width: ToolbarConstants.tapTargetSize, height: ToolbarConstants.tapTargetSize)
                .contentShape(Circle())
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
        .padding(toolbarAxis == .horizontal ? .horizontal : .vertical, 8)
        .padding(toolbarAxis == .horizontal ? .vertical : .horizontal, 8)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color("ToolbarBackground"))
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
        }
        .onAppear { updateUndoState() }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidUndoChange)) { _ in updateUndoState() }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidRedoChange)) { _ in updateUndoState() }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidCloseUndoGroup)) { _ in updateUndoState() }
    }

    @ViewBuilder
    private var dividerView: some View {
        if toolbarAxis == .horizontal {
            Divider().frame(height: 36)
        } else {
            Divider().frame(width: 36)
        }
    }

    private func updateUndoState() {
        canUndo = undoManager?.canUndo ?? false
        canRedo = undoManager?.canRedo ?? false
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
        .frame(width: ToolbarConstants.tapTargetSize, height: ToolbarConstants.tapTargetSize)
        .contentShape(Rectangle())
        .scaleEffect(isDragged ? (isDraggingOutOfBounds ? 0.8 : 1.05) : 1.0)
        .shadow(color: isDragged && !isDraggingOutOfBounds ? .black.opacity(0.2) : .clear, radius: 4, x: 0, y: 2)
        .offset(isDragged ? dragTranslation : mainAxisOffset(reorderDisplacement(for: icon)))
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

                    if draggedIconID != icon.id {
                        draggedIconID = icon.id
                        let isColor = icon.type == .color
                        dragZoneIsColor = isColor
                        let zone = isColor ? colorIcons : toolIcons
                        let zoneIdx = zone.firstIndex(where: { $0.id == icon.id }) ?? 0
                        dragStartZoneIndex = zoneIdx
                        proposedZoneIndex = zoneIdx
                    }

                    dragTranslation = translation

                    let crossAxis = abs(crossAxisValue(translation))
                    let canDelete: Bool = {
                        if !icon.isEssential { return true }
                        return toolbarIcons.filter { $0.type == icon.type }.count > 1
                    }()

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

                    guard !isDraggingOutOfBounds,
                          let startIdx = dragStartZoneIndex,
                          let curProposed = proposedZoneIndex else { return }

                    let mainDelta = mainAxisValue(translation)
                    let proposedSlotHome = CGFloat(curProposed - startIdx) * slotPitch
                    let deltaFromProposed = mainDelta - proposedSlotHome
                    let threshold = slotPitch * 0.5

                    var newProposed = curProposed
                    if deltaFromProposed > threshold {
                        newProposed = curProposed + 1
                    } else if deltaFromProposed < -threshold {
                        newProposed = curProposed - 1
                    }

                    let zone = dragZoneIsColor ? colorIcons : toolIcons
                    let clamped = max(0, min(newProposed, zone.count - 1))

                    if clamped != curProposed {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.86)) {
                            proposedZoneIndex = clamped
                        }
                    }
                }
                .onEnded { value in
                    let distance = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))
                    if distance < 5 {
                        handleIconTap(icon)
                    }

                    if let startIdx = dragStartZoneIndex,
                       let targetIdx = proposedZoneIndex,
                       startIdx != targetIdx {
                        moveIconInZone(id: icon.id, toZoneIndex: targetIdx, isColor: dragZoneIsColor)
                        let layoutDelta = CGFloat(startIdx - targetIdx) * slotPitch
                        if toolbarAxis == .vertical {
                            dragTranslation.height += layoutDelta
                        } else {
                            dragTranslation.width += layoutDelta
                        }
                    }

                    dragStartZoneIndex = nil
                    proposedZoneIndex = nil
                    dragZoneIsColor = false

                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        draggedIconID = nil
                        dragTranslation = .zero
                        isDraggingOutOfBounds = false
                    }
                }
        )
    }

    // MARK: - Reorder Commit
    private func moveIconInZone(id: UUID, toZoneIndex target: Int, isColor: Bool) {
        guard let currentFlatIndex = toolbarIcons.firstIndex(where: { $0.id == id }) else { return }
        let icon = toolbarIcons.remove(at: currentFlatIndex)
        let newZoneIndices = toolbarIcons.indices.filter {
            isColor ? toolbarIcons[$0].type == .color : toolbarIcons[$0].type != .color
        }
        let clampedTarget = min(max(target, 0), newZoneIndices.count)
        let insertAt: Int
        if clampedTarget >= newZoneIndices.count {
            if let last = newZoneIndices.last {
                insertAt = last + 1
            } else {
                insertAt = isColor ? toolbarIcons.count : 0
            }
        } else {
            insertAt = newZoneIndices[clampedTarget]
        }
        toolbarIcons.insert(icon, at: insertAt)
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
            .font(.system(size: 16))
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
                editingIconID = icon.id
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
