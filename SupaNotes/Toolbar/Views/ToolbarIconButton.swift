import SwiftUI

struct ToolbarIconButton: View {
    let icon: ToolbarIcon
    @Binding var toolbarIcons: [ToolbarIcon]
    @Binding var colorSelectedByUser: Color
    @Binding var currentlyActiveTool: ActiveTool
    var didRepositionToolbar: Bool
    var iconIDBeingEdited: Binding<UUID?>

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if icon.type == .color, let color = icon.color {
                // Show a colored circle for color choices
                colorIconView(color: color)
            } else {
                // Show an icon for tools (Pen, Eraser, etc.)
                toolIconView()
            }
        }
        .frame(width: ToolbarConstants.tapTargetSize, height: ToolbarConstants.tapTargetSize)
        .contentShape(Rectangle())
        .popover(isPresented: Binding(
            get: { iconIDBeingEdited.wrappedValue == icon.id },
            set: { if !$0 { iconIDBeingEdited.wrappedValue = nil } }
        )) {
            // This is the little menu that pops up when you tap a tool twice
            popoverContent()
        }
        .onTapGesture {
            // Don't do anything if the user was just dragging the toolbar
            guard !didRepositionToolbar else { return }
            handleIconTap()
        }
    }

    private func colorIconView(color: Color) -> some View {
        let isDrawingTool = currentlyActiveTool == .pen || currentlyActiveTool == .highlighter
        return ColorSwatchView(
            color: color,
            showCheckmark: isDrawingTool && colorSelectedByUser.isSimilar(to: color, colorScheme: colorScheme)
        )
    }

    private func toolIconView() -> some View {
        let isThisToolActive = doesToolMatchIconType(icon.type)
        return Image(systemName: icon.type.iconName)
            .font(.system(size: Design.FontSize.toolIcon))
            .fontWeight(isThisToolActive ? .bold : .regular)
            .scaleEffect(isThisToolActive ? 1.2 : 1.0)
            .frame(width: Design.Layout.colorSwatchSize, height: Design.Layout.colorSwatchSize)
            .foregroundStyle(toolForeground(for: icon.type, isActive: isThisToolActive))
    }

    private func toolForeground(for type: ToolType, isActive: Bool) -> some ShapeStyle {
        if !isActive { return AnyShapeStyle(.secondary) }
        switch type {
        case .pen, .highlighter:
            // Use the user's selected color for drawing tools
            return AnyShapeStyle(colorSelectedByUser)
        default:
            return AnyShapeStyle(.primary)
        }
    }

    private func doesToolMatchIconType(_ type: ToolType) -> Bool {
        switch type {
        case .pen: return currentlyActiveTool == .pen
        case .eraser: return currentlyActiveTool == .eraser
        case .highlighter: return currentlyActiveTool == .highlighter
        case .lasso: return currentlyActiveTool == .lasso
        default: return false
        }
    }

    private func toolFor(_ type: ToolType) -> ActiveTool {
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
                selectedColor: $colorSelectedByUser
            )
        } else if icon.type.isWritingInstrument,
                  let index = toolbarIcons.firstIndex(where: { $0.id == icon.id }) {
            let range = sliderRange(for: icon.type)
            let opacity: Double = icon.type == .highlighter ? 0.4 : 1.0
            let color = icon.type == .eraser ? Color.primary : colorSelectedByUser
            InstrumentPopoverView(
                settings: $toolbarIcons[index].instrumentSettings ?? .constant(.pen()),
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
                // If this color is already selected, open the editor. Otherwise, select it.
                if (currentlyActiveTool == .pen || currentlyActiveTool == .highlighter) && colorSelectedByUser.isSimilar(to: color, colorScheme: colorScheme) {
                    iconIDBeingEdited.wrappedValue = icon.id
                } else {
                    colorSelectedByUser = color
                    // Auto-switch to pen if the user picks a color while using the eraser
                    if currentlyActiveTool == .eraser || currentlyActiveTool == .lasso {
                        currentlyActiveTool = .pen
                    }
                }
            }
        case .pen, .eraser, .highlighter:
            let targetTool = toolFor(icon.type)
            // If the tool is already active, open its settings. Otherwise, switch to it.
            if currentlyActiveTool == targetTool {
                iconIDBeingEdited.wrappedValue = icon.id
            } else {
                currentlyActiveTool = targetTool
            }
        case .lasso:
            currentlyActiveTool = .lasso
        }
    }
}
