import SwiftUI

struct DrawingToolbar: View {
    @Bindable var toolbar: ToolbarState
    var undoManager: UndoManager?

    @State private var showColorPicker = false
    @State private var editingIconID: UUID?
    @State private var lastDeletedColor: Color = .blue

    @State private var positioning = ToolbarPositioning()
    @State private var toolbarDragOffset: CGSize = .zero
    @State private var isDraggingToolbar = false
    @State private var didRepositionToolbar = false

    private var toolIcons: [ToolbarIcon] { toolbar.toolbarIcons.filter { $0.type != .color } }
    private var colorIcons: [ToolbarIcon] { toolbar.toolbarIcons.filter { $0.type == .color } }

    var body: some View {
        GeometryReader { geometry in
            toolbarContent
                .fixedSize()
                .simultaneousGesture(
                    ToolbarPositioning.repositionGesture(
                        draggedIconID: nil,
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
        .fullScreenCover(isPresented: $toolbar.showCustomization) {
            customizationOverlay
        }
    }

    @ViewBuilder
    private var toolbarContent: some View {
        let layout = positioning.axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: 2))
            : AnyLayout(VStackLayout(spacing: 2))

        layout {
            ForEach(Array(toolbar.sectionOrder.enumerated()), id: \.element) { idx, section in
                sectionView(section)
                if idx < toolbar.sectionOrder.count - 1, isSectionVisible(section) {
                    dividerView
                }
            }
            cogButton
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

    private func isSectionVisible(_ section: ToolbarSection) -> Bool {
        switch section {
        case .undoRedo: return toolbar.showUndoRedo
        case .tools: return !toolIcons.isEmpty
        case .colors: return !colorIcons.isEmpty
        }
    }

    @ViewBuilder
    private func sectionView(_ section: ToolbarSection) -> some View {
        switch section {
        case .undoRedo:
            if toolbar.showUndoRedo {
                UndoRedoButtons(undoManager: undoManager, didRepositionToolbar: didRepositionToolbar)
            }
        case .tools:
            ForEach(toolIcons) { icon in
                ToolbarIconButton(
                    icon: icon,
                    toolbarIcons: $toolbar.toolbarIcons,
                    selectedColor: $toolbar.selectedColor,
                    activeTool: $toolbar.activeTool,
                    didRepositionToolbar: didRepositionToolbar,
                    editingIconID: $editingIconID
                )
            }
        case .colors:
            ForEach(colorIcons) { icon in
                ToolbarIconButton(
                    icon: icon,
                    toolbarIcons: $toolbar.toolbarIcons,
                    selectedColor: $toolbar.selectedColor,
                    activeTool: $toolbar.activeTool,
                    didRepositionToolbar: didRepositionToolbar,
                    editingIconID: $editingIconID
                )
            }
            addColorButton
        }
    }

    private var addColorButton: some View {
        Button {
            guard !didRepositionToolbar else { return }
            showColorPicker = true
        } label: {
            Image(systemName: "plus.circle.dashed")
                .font(.system(size: Design.Layout.plusButtonSize * 0.75, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: ToolbarConstants.tapTargetSize, height: ToolbarConstants.tapTargetSize)
                .contentShape(Circle())
        }
        .popover(isPresented: $showColorPicker) {
            AddColorView(
                toolbarIcons: $toolbar.toolbarIcons,
                selectedColor: $toolbar.selectedColor,
                activeTool: $toolbar.activeTool,
                defaultColor: lastDeletedColor,
                onBack: { showColorPicker = false }
            )
        }
    }

    private var cogButton: some View {
        Button {
            guard !didRepositionToolbar else { return }
            toolbar.showCustomization = true
        } label: {
            plusCogLabel(systemName: "gearshape.fill")
        }
    }

    private func plusCogLabel(systemName: String) -> some View {
        ZStack {
            Circle()
                .fill(Color.secondary.opacity(0.15))
                .frame(width: Design.Layout.plusButtonSize, height: Design.Layout.plusButtonSize)
            Image(systemName: systemName)
                .font(.system(size: Design.FontSize.plusIcon, weight: .bold))
                .foregroundStyle(.primary)
        }
        .overlay {
            Circle().stroke(Color.primary.opacity(0.3), lineWidth: 1)
        }
        .frame(width: ToolbarConstants.tapTargetSize, height: ToolbarConstants.tapTargetSize)
        .contentShape(Circle())
    }

    @ViewBuilder
    private var dividerView: some View {
        if positioning.axis == .horizontal {
            Divider().frame(height: Design.Layout.headerButtonSize)
        } else {
            Divider().frame(width: Design.Layout.headerButtonSize)
        }
    }

    private var customizationOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .background(.ultraThinMaterial)
                .onTapGesture { toolbar.showCustomization = false }
            ToolbarCustomizationView(toolbar: toolbar) {
                toolbar.showCustomization = false
            }
        }
        .presentationBackground(.clear)
    }
}
