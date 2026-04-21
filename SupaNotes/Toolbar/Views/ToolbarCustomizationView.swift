import SwiftUI

struct ToolbarCustomizationView: View {
    @Bindable var toolbar: ToolbarState
    var onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var showAddColor = false
    @State private var isRearranging = false
    @State private var positioning = ToolbarPositioning()

    private var toolRows: [ToolbarIcon] {
        toolbar.toolbarIcons.filter { $0.type != .color }
    }

    private var colorRows: [ToolbarIcon] {
        toolbar.toolbarIcons.filter { $0.type == .color }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if positioning.axis == .horizontal {
                previewBlock
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .frame(height: 140)
                    .background(Color.secondary.opacity(0.06))
                Divider()
                settingsScroll
            } else {
                HStack(alignment: .top, spacing: 0) {
                    previewBlock
                        .frame(width: 200)
                        .padding(16)
                        .frame(maxHeight: .infinity)
                        .background(Color.secondary.opacity(0.06))
                    Divider()
                    settingsScroll
                }
            }
        }
        .frame(width: 640, height: 560)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(UIColor.systemBackground))
                .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        )
        .sheet(isPresented: $showAddColor) {
            AddColorView(
                toolbarIcons: $toolbar.toolbarIcons,
                selectedColor: $toolbar.colorSelectedByUser,
                activeTool: $toolbar.currentlyActiveTool,
                defaultColor: .blue,
                onBack: { showAddColor = false }
            )
            .presentationDetents([.medium])
        }
    }

    private var settingsScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                rearrangeToggle
                layoutBlock
                toolsBlock
                colorsBlock
                if !isRearranging { resetButton }
            }
            .padding(20)
        }
    }

    private var previewBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview").font(.subheadline).foregroundStyle(.secondary)
            ToolbarCustomizationPreview(toolbar: toolbar)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var header: some View {
        HStack {
            Text("Customize Toolbar").font(.headline)
            Spacer()
            Button(action: {
                if isRearranging {
                    withAnimation(.easeInOut(duration: 0.2)) { isRearranging = false }
                } else {
                    onDismiss()
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    private var rearrangeToggle: some View {
        Toggle(isOn: $isRearranging.animation(.easeInOut(duration: 0.2))) {
            Text("Rearrange").font(.subheadline)
        }
    }

    // MARK: - Layout

    private var layoutBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Layout").font(.subheadline).foregroundStyle(.secondary)
            ReorderableList(
                items: toolbar.sectionOrder,
                isEditing: isRearranging,
                rowHeight: 44,
                spacing: 6,
                onMove: { id, to in moveSection(id: id, to: to) },
                onDragChange: { id in
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                        toolbar.previewDraggedSection = id.flatMap { ToolbarSection(rawValue: $0) }
                    }
                }
            ) { section in
                layoutRow(section: section)
            }
        }
    }

    private func moveSection(id: String, to: Int) {
        guard let from = toolbar.sectionOrder.firstIndex(where: { $0.id == id }) else { return }
        let item = toolbar.sectionOrder.remove(at: from)
        let clamped = max(0, min(to, toolbar.sectionOrder.count))
        toolbar.sectionOrder.insert(item, at: clamped)
    }

    private func layoutRow(section: ToolbarSection) -> some View {
        HStack {
            Text(section.displayName)
            Spacer()
            if !isRearranging, section == .undoRedo {
                Toggle("", isOn: $toolbar.showUndoRedo).labelsHidden()
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Tools

    private var toolsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tools").font(.subheadline).foregroundStyle(.secondary)
            if isRearranging {
                ReorderableList(
                    items: toolRows,
                    isEditing: true,
                    rowHeight: 44,
                    spacing: 6,
                    onMove: { id, to in
                        toolbar.toolbarIcons.moveIconInZone(id: id, toZoneIndex: to, isColor: false)
                    },
                    onDragChange: { id in
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            toolbar.previewDraggedIconID = id
                        }
                    }
                ) { icon in
                    toolDisplayRow(icon: icon)
                }
            } else {
                VStack(spacing: 6) {
                    ForEach([ToolType.pen, .eraser], id: \.self) { type in
                        toolToggleRow(type: type)
                    }
                }
            }
        }
    }

    private func toolDisplayRow(icon: ToolbarIcon) -> some View {
        HStack {
            Image(systemName: icon.type.iconName).frame(width: 24)
            Text(icon.type.displayName)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func toolToggleRow(type: ToolType) -> some View {
        let present = toolbar.toolbarIcons.contains(where: { $0.type == type })
        return HStack {
            Image(systemName: type.iconName).frame(width: 24)
            Text(type.displayName)
            Spacer()
            Toggle("", isOn: Binding(
                get: { present },
                set: { newValue in toggleTool(type, on: newValue) }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func toggleTool(_ type: ToolType, on: Bool) {
        if on {
            guard !toolbar.toolbarIcons.contains(where: { $0.type == type }) else { return }
            toolbar.toolbarIcons.appendToZone(ToolbarIcon.toolIcon(type))
        } else {
            toolbar.toolbarIcons.removeAll { $0.type == type }
        }
    }

    // MARK: - Colors

    private var colorsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Colors").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if !isRearranging {
                    Button { showAddColor = true } label: {
                        Label("Add", systemImage: "plus.circle.fill").font(.subheadline)
                    }
                }
            }
            ReorderableList(
                items: colorRows,
                isEditing: isRearranging,
                rowHeight: 44,
                spacing: 6,
                onMove: { id, to in
                    toolbar.toolbarIcons.moveIconInZone(id: id, toZoneIndex: to, isColor: true)
                },
                onDragChange: { id in
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                        toolbar.previewDraggedIconID = id
                    }
                }
            ) { icon in
                colorRow(icon: icon)
            }
        }
    }

    private func colorRow(icon: ToolbarIcon) -> some View {
        HStack {
            Circle()
                .fill(icon.color ?? .gray)
                .frame(width: 22, height: 22)
                .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1))
            Text(icon.name)
            Spacer()
            if !isRearranging {
                Button { removeColor(id: icon.id) } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(colorRows.count <= 1 ? Color.secondary.opacity(0.4) : Color.red)
                }
                .buttonStyle(.borderless)
                .disabled(colorRows.count <= 1)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func removeColor(id: UUID) {
        guard colorRows.count > 1 else { return }
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            toolbar.toolbarIcons.removeAll { $0.id == id }
        }
    }

    // MARK: - Reset

    private var resetButton: some View {
        Button(role: .destructive) {
            withAnimation { toolbar.resetToDefaults(colorScheme: colorScheme) }
        } label: {
            HStack {
                Image(systemName: "arrow.counterclockwise")
                Text("Reset to Default")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.bordered)
    }
}
