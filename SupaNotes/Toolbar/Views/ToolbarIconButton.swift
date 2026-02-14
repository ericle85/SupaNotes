import SwiftUI

struct ToolbarIconButton: View {
    let icon: ToolbarIcon
    @Binding var toolbarIcons: [ToolbarIcon]
    @Binding var selectedColor: Color
    @Binding var activeTool: ActiveTool
    let positioning: ToolbarPositioning
    let dragState: IconDragState
    let toolIcons: [ToolbarIcon]
    let colorIcons: [ToolbarIcon]
    var didRepositionToolbar: Bool
    var lastDeletedColor: Binding<Color>
    var editingIconID: Binding<UUID?>

    @Environment(\.colorScheme) private var colorScheme

    private let slotPitch: CGFloat = ToolbarConstants.tapTargetSize + 2

    var body: some View {
        let isDragged = dragState.draggedIconID == icon.id
        Group {
            if icon.type == .color, let color = icon.color {
                colorIconView(color: color)
            } else {
                toolIconView()
            }
        }
        .frame(width: ToolbarConstants.tapTargetSize, height: ToolbarConstants.tapTargetSize)
        .contentShape(Rectangle())
        .scaleEffect(isDragged ? (dragState.isDraggingOutOfBounds ? 0.8 : 1.05) : 1.0)
        .shadow(color: isDragged && !dragState.isDraggingOutOfBounds ? .black.opacity(0.2) : .clear, radius: 4, x: 0, y: 2)
        .offset(isDragged ? dragState.dragTranslation : positioning.mainAxisOffset(
            dragState.reorderDisplacement(for: icon, toolIcons: toolIcons, colorIcons: colorIcons, slotPitch: slotPitch)
        ))
        .zIndex(isDragged ? 100 : 0)
        .popover(isPresented: Binding(
            get: { editingIconID.wrappedValue == icon.id },
            set: { if !$0 { editingIconID.wrappedValue = nil } }
        )) {
            popoverContent()
        }
        .gesture(dragGesture())
    }

    // MARK: - Color Icon
    private func colorIconView(color: Color) -> some View {
        let isDrawingTool = activeTool == .pen || activeTool == .highlighter
        return ColorSwatchView(
            color: color,
            showCheckmark: isDrawingTool && selectedColor.isSimilar(to: color, colorScheme: colorScheme)
        )
    }

    // MARK: - Tool Icon
    private func toolIconView() -> some View {
        let isActive = activeToolMatches(icon.type)
        return Image(systemName: icon.type.iconName)
            .font(.system(size: Design.FontSize.toolIcon))
            .fontWeight(isActive ? .bold : .regular)
            .scaleEffect(isActive ? 1.2 : 1.0)
            .frame(width: Design.Layout.colorSwatchSize, height: Design.Layout.colorSwatchSize)
            .foregroundStyle(toolForeground(for: icon.type, isActive: isActive))
    }

    private func toolForeground(for type: ToolType, isActive: Bool) -> some ShapeStyle {
        if !isActive { return AnyShapeStyle(.secondary) }
        switch type {
        case .pen, .highlighter:
            return AnyShapeStyle(selectedColor)
        default:
            return AnyShapeStyle(.primary)
        }
    }

    private func activeToolMatches(_ type: ToolType) -> Bool {
        switch type {
        case .pen: return activeTool == .pen
        case .eraser: return activeTool == .eraser
        case .highlighter: return activeTool == .highlighter
        case .lasso: return activeTool == .lasso
        default: return false
        }
    }

    private func activeToolFor(_ type: ToolType) -> ActiveTool {
        switch type {
        case .pen: return .pen
        case .eraser: return .eraser
        case .highlighter: return .highlighter
        case .lasso: return .lasso
        default: return .pen
        }
    }

    // MARK: - Popover Content
    @ViewBuilder
    private func popoverContent() -> some View {
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
        case .pen: return Design.SliderRange.pen
        case .eraser: return Design.SliderRange.eraser
        case .highlighter: return Design.SliderRange.highlighter
        default: return Design.SliderRange.pen
        }
    }

    // MARK: - Tap Handler
    private func handleIconTap() {
        switch icon.type {
        case .color:
            if let color = icon.color {
                if (activeTool == .pen || activeTool == .highlighter) && selectedColor.isSimilar(to: color, colorScheme: colorScheme) {
                    editingIconID.wrappedValue = icon.id
                } else {
                    selectedColor = color
                    if activeTool == .eraser || activeTool == .lasso {
                        activeTool = .pen
                    }
                }
            }
        case .pen, .eraser, .highlighter:
            let targetTool = activeToolFor(icon.type)
            if activeTool == targetTool {
                editingIconID.wrappedValue = icon.id
            } else {
                activeTool = targetTool
            }
        case .lasso:
            activeTool = .lasso
        default:
            break
        }
    }

    // MARK: - Drag Gesture
    private func dragGesture() -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let translation = value.translation
                guard abs(translation.width) > Design.Drag.reorderMinDistance || abs(translation.height) > Design.Drag.reorderMinDistance else { return }

                if dragState.draggedIconID != icon.id {
                    dragState.draggedIconID = icon.id
                    let isColor = icon.type == .color
                    dragState.dragZoneIsColor = isColor
                    let zone = isColor ? colorIcons : toolIcons
                    let zoneIdx = zone.firstIndex(where: { $0.id == icon.id }) ?? 0
                    dragState.dragStartZoneIndex = zoneIdx
                    dragState.proposedZoneIndex = zoneIdx
                }

                dragState.dragTranslation = translation

                let crossAxis = abs(positioning.crossAxisValue(translation))
                let canDelete: Bool = {
                    if !icon.isEssential { return true }
                    return toolbarIcons.filter { $0.type == icon.type }.count > 1
                }()

                if crossAxis > Design.Drag.deleteThreshold && !dragState.isDraggingOutOfBounds && canDelete {
                    dragState.isDraggingOutOfBounds = true
                    if icon.type == .color, let deletedColor = icon.color {
                        lastDeletedColor.wrappedValue = deletedColor
                    }
                    withAnimation(.spring(response: 0.4, dampingFraction: Design.Animation.springDamping)) {
                        toolbarIcons.removeAll { $0.id == icon.id }
                    }
                    return
                }

                guard !dragState.isDraggingOutOfBounds,
                      let startIdx = dragState.dragStartZoneIndex,
                      let curProposed = dragState.proposedZoneIndex else { return }

                let mainDelta = positioning.mainAxisValue(translation)
                let proposedSlotHome = CGFloat(curProposed - startIdx) * slotPitch
                let deltaFromProposed = mainDelta - proposedSlotHome
                let threshold = slotPitch * 0.5

                var newProposed = curProposed
                if deltaFromProposed > threshold {
                    newProposed = curProposed + 1
                } else if deltaFromProposed < -threshold {
                    newProposed = curProposed - 1
                }

                let zone = dragState.dragZoneIsColor ? colorIcons : toolIcons
                let clamped = max(0, min(newProposed, zone.count - 1))

                if clamped != curProposed {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.86)) {
                        dragState.proposedZoneIndex = clamped
                    }
                }
            }
            .onEnded { value in
                let distance = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))
                if distance < Design.Drag.tapMaxDistance {
                    handleIconTap()
                }

                if let startIdx = dragState.dragStartZoneIndex,
                   let targetIdx = dragState.proposedZoneIndex,
                   startIdx != targetIdx {
                    toolbarIcons.moveIconInZone(id: icon.id, toZoneIndex: targetIdx, isColor: dragState.dragZoneIsColor)
                    let layoutDelta = CGFloat(startIdx - targetIdx) * slotPitch
                    if positioning.axis == .vertical {
                        dragState.dragTranslation.height += layoutDelta
                    } else {
                        dragState.dragTranslation.width += layoutDelta
                    }
                }

                dragState.reset()
            }
    }
}
