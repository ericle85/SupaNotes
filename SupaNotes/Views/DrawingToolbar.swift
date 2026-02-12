import SwiftUI
import PencilKit

struct DrawingToolbar: View {
    @Binding var selectedColor: Color
    @Binding var penWidth: CGFloat
    @Binding var eraserWidth: CGFloat
    @Binding var isErasing: Bool
    var undoManager: UndoManager?
    @Environment(\.colorScheme) private var colorScheme

    @State private var showColorPicker = false
    @State private var showPenSlider = false
    @State private var showEraserSlider = false
    @State private var editingColorID: UUID?  // Track which color is being edited

    @State private var toolbarIcons: [ToolbarIcon] = [
          .colorIcon(.black, name: "Black"),
          .colorIcon(.red, name: "Red"),
          .colorIcon(.blue, name: "Blue"),
          .colorIcon(.green, name: "Green"),
      ]

    // Drag-to-delete state
    @State private var draggedIconID: UUID?
    @State private var dragOffset: CGSize = .zero
    @State private var isOutOfBounds = false
    @State private var lastDeletedColor: Color = .blue

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
                        if !isErasing && selectedColor.isSimilar(to: color, colorScheme: colorScheme) {
                            Image(systemName: "checkmark")
                                .font(.caption2.bold())
                                .foregroundStyle(color.isLight(colorScheme: colorScheme) ? .black : .white)
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
                            if !isErasing && selectedColor.isSimilar(to: color, colorScheme: colorScheme) {
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
