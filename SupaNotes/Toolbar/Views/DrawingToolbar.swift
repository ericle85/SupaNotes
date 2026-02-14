import SwiftUI

struct DrawingToolbar: View {
    @Binding var toolbarIcons: [ToolbarIcon]
    @Binding var selectedColor: Color
    @Binding var activeTool: ActiveTool
    var undoManager: UndoManager?

    @State private var showColorPicker = false
    @State private var editingIconID: UUID?
    @State private var dragState = IconDragState()
    @State private var lastDeletedColor: Color = .blue

    // Toolbar repositioning
    @State private var positioning = ToolbarPositioning()
    @State private var toolbarDragOffset: CGSize = .zero
    @State private var isDraggingToolbar = false
    @State private var didRepositionToolbar = false

    private var toolIcons: [ToolbarIcon] { toolbarIcons.filter { $0.type != .color } }
    private var colorIcons: [ToolbarIcon] { toolbarIcons.filter { $0.type == .color } }

    var body: some View {
        GeometryReader { geometry in
            toolbarContent
                .fixedSize()
                .simultaneousGesture(
                    ToolbarPositioning.repositionGesture(
                        draggedIconID: dragState.draggedIconID,
                        isDraggingToolbar: $isDraggingToolbar,
                        didRepositionToolbar: $didRepositionToolbar,
                        toolbarDragOffset: $toolbarDragOffset,
                        toolbarEdge: $positioning.toolbarEdge,
                        screenSize: geometry.size
                    )
                )
                .offset(isDraggingToolbar ? toolbarDragOffset : .zero)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: positioning.alignment)
                .padding(.vertical, 0)
                .padding(.horizontal, positioning.edge == .leading || positioning.edge == .trailing ? Design.Spacing.toolbarEdgePadding : 0)
        }
    }

    @ViewBuilder
    private var toolbarContent: some View {
        let layout = positioning.axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: 2))
            : AnyLayout(VStackLayout(spacing: 2))

        layout {
            UndoRedoButtons(undoManager: undoManager, didRepositionToolbar: didRepositionToolbar)

            dividerView

            ForEach(toolIcons) { icon in
                ToolbarIconButton(
                    icon: icon,
                    toolbarIcons: $toolbarIcons,
                    selectedColor: $selectedColor,
                    activeTool: $activeTool,
                    positioning: positioning,
                    dragState: dragState,
                    toolIcons: toolIcons,
                    colorIcons: colorIcons,
                    didRepositionToolbar: didRepositionToolbar,
                    lastDeletedColor: $lastDeletedColor,
                    editingIconID: $editingIconID
                )
            }

            dividerView

            ForEach(colorIcons) { icon in
                ToolbarIconButton(
                    icon: icon,
                    toolbarIcons: $toolbarIcons,
                    selectedColor: $selectedColor,
                    activeTool: $activeTool,
                    positioning: positioning,
                    dragState: dragState,
                    toolIcons: toolIcons,
                    colorIcons: colorIcons,
                    didRepositionToolbar: didRepositionToolbar,
                    lastDeletedColor: $lastDeletedColor,
                    editingIconID: $editingIconID
                )
            }

            // Plus button
            Button {
                guard !didRepositionToolbar else { return }
                showColorPicker = true
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: Design.Layout.plusButtonSize, height: Design.Layout.plusButtonSize)
                    Image(systemName: "plus")
                        .font(.system(size: Design.FontSize.plusIcon, weight: .bold))
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
        .padding(positioning.axis == .horizontal ? .horizontal : .vertical, Design.Spacing.toolbarPadding)
        .padding(positioning.axis == .horizontal ? .vertical : .horizontal, Design.Spacing.toolbarPadding)
        .background {
            RoundedRectangle(cornerRadius: Design.CornerRadius.toolbar)
                .fill(Color("ToolbarBackground"))
                .shadow(
                    color: .black.opacity(Design.Shadow.toolbar.color),
                    radius: Design.Shadow.toolbar.radius,
                    x: Design.Shadow.toolbar.x,
                    y: Design.Shadow.toolbar.y
                )
        }
    }

    @ViewBuilder
    private var dividerView: some View {
        if positioning.axis == .horizontal {
            Divider().frame(height: Design.Layout.headerButtonSize)
        } else {
            Divider().frame(width: Design.Layout.headerButtonSize)
        }
    }
}
