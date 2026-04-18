import SwiftUI

struct ToolbarIconButton: View {
    let icon: ToolbarIcon
    @Binding var toolbarIcons: [ToolbarIcon]
    @Binding var selectedColor: Color
    @Binding var activeTool: ActiveTool
    var didRepositionToolbar: Bool
    var editingIconID: Binding<UUID?>

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if icon.type == .color, let color = icon.color {
                colorIconView(color: color)
            } else {
                toolIconView()
            }
        }
        .frame(width: ToolbarConstants.tapTargetSize, height: ToolbarConstants.tapTargetSize)
        .contentShape(Rectangle())
        .popover(isPresented: Binding(
            get: { editingIconID.wrappedValue == icon.id },
            set: { if !$0 { editingIconID.wrappedValue = nil } }
        )) {
            popoverContent()
        }
        .onTapGesture {
            guard !didRepositionToolbar else { return }
            handleIconTap()
        }
    }

    private func colorIconView(color: Color) -> some View {
        let isDrawingTool = activeTool == .pen || activeTool == .highlighter
        return ColorSwatchView(
            color: color,
            showCheckmark: isDrawingTool && selectedColor.isSimilar(to: color, colorScheme: colorScheme)
        )
    }

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
        }
    }
}
