import SwiftUI

struct ToolbarCustomizationView: View {
    @Bindable var toolbar: ToolbarState
    var onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var showAddColor = false

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
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    sectionOrderBlock
                    toolsBlock
                    colorsBlock
                    resetButton
                }
                .padding(20)
            }
        }
        .frame(width: 380, height: 560)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(UIColor.systemBackground))
                .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        )
        .sheet(isPresented: $showAddColor) {
            AddColorView(
                toolbarIcons: $toolbar.toolbarIcons,
                selectedColor: $toolbar.selectedColor,
                activeTool: $toolbar.activeTool,
                defaultColor: .blue,
                onBack: { showAddColor = false }
            )
            .presentationDetents([.medium])
        }
    }

    private var header: some View {
        HStack {
            Text("Customize Toolbar").font(.headline)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    private var sectionOrderBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Layout").font(.subheadline).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(Array(toolbar.sectionOrder.enumerated()), id: \.element) { idx, section in
                    sectionRow(section: section, index: idx)
                    if idx < toolbar.sectionOrder.count - 1 { Divider() }
                }
            }
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func sectionRow(section: ToolbarSection, index: Int) -> some View {
        HStack {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
            Text(section.displayName)
            Spacer()
            if section == .undoRedo {
                Toggle("", isOn: $toolbar.showUndoRedo).labelsHidden()
            }
            HStack(spacing: 4) {
                Button { move(from: index, to: index - 1) } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(index == 0)
                Button { move(from: index, to: index + 1) } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(index == toolbar.sectionOrder.count - 1)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
    }

    private func move(from: Int, to: Int) {
        guard to >= 0, to < toolbar.sectionOrder.count else { return }
        let item = toolbar.sectionOrder.remove(at: from)
        toolbar.sectionOrder.insert(item, at: to)
    }

    private var toolsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tools").font(.subheadline).foregroundStyle(.secondary)
            VStack(spacing: 6) {
                ForEach([ToolType.pen, .eraser, .highlighter, .lasso], id: \.self) { type in
                    toolToggleRow(type: type)
                }
            }
        }
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

    private var colorsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Colors").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button {
                    showAddColor = true
                } label: {
                    Label("Add", systemImage: "plus.circle.fill").font(.subheadline)
                }
            }
            VStack(spacing: 6) {
                ForEach(Array(colorRows.enumerated()), id: \.element.id) { idx, icon in
                    colorRow(icon: icon, index: idx)
                }
            }
        }
    }

    private func colorRow(icon: ToolbarIcon, index: Int) -> some View {
        HStack {
            Circle()
                .fill(icon.color ?? .gray)
                .frame(width: 22, height: 22)
                .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1))
            Text(icon.name)
            Spacer()
            HStack(spacing: 4) {
                Button { moveColor(from: index, to: index - 1) } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(index == 0)
                Button { moveColor(from: index, to: index + 1) } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(index == colorRows.count - 1)
                Button {
                    removeColor(id: icon.id)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(colorRows.count <= 1 ? Color.secondary.opacity(0.4) : Color.red)
                }
                .disabled(colorRows.count <= 1)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func moveColor(from: Int, to: Int) {
        let colors = colorRows
        guard to >= 0, to < colors.count else { return }
        let moving = colors[from]
        guard let srcFlat = toolbar.toolbarIcons.firstIndex(where: { $0.id == moving.id }) else { return }
        toolbar.toolbarIcons.remove(at: srcFlat)
        let remainingColors = toolbar.toolbarIcons.indices.filter { toolbar.toolbarIcons[$0].type == .color }
        let insertAt: Int
        if to >= remainingColors.count {
            insertAt = (remainingColors.last.map { $0 + 1 }) ?? toolbar.toolbarIcons.count
        } else {
            insertAt = remainingColors[to]
        }
        toolbar.toolbarIcons.insert(moving, at: insertAt)
    }

    private func removeColor(id: UUID) {
        guard colorRows.count > 1 else { return }
        toolbar.toolbarIcons.removeAll { $0.id == id }
    }

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
