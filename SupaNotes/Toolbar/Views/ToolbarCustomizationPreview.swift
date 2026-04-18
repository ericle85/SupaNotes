import SwiftUI

struct ToolbarCustomizationPreview: View {
    @Bindable var toolbar: ToolbarState
    @State private var positioning = ToolbarPositioning()

    private var toolIcons: [ToolbarIcon] { toolbar.toolbarIcons.filter { $0.type != .color } }
    private var colorIcons: [ToolbarIcon] { toolbar.toolbarIcons.filter { $0.type == .color } }

    var body: some View {
        Group {
            if positioning.axis == .horizontal {
                horizontalContent
            } else {
                verticalContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var visibleSections: [ToolbarSection] {
        toolbar.sectionOrder.filter { sectionHasContent($0) }
    }

    private func iconCount(_ section: ToolbarSection) -> Int {
        switch section {
        case .undoRedo: return 2
        case .tools: return toolIcons.count
        case .colors: return colorIcons.count
        }
    }

    private func sectionExtent(_ section: ToolbarSection) -> CGFloat {
        let n = iconCount(section)
        return CGFloat(n) * ToolbarConstants.tapTargetSize + CGFloat(max(0, n - 1)) * 2
    }

    private var horizontalContent: some View {
        VStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(Array(visibleSections.enumerated()), id: \.element) { idx, section in
                    HStack(spacing: 2) { sectionContent(section) }
                    if idx < visibleSections.count - 1 { dividerView }
                }
            }
            .padding(Design.Spacing.toolbarPadding)
            .background(barBackground)

            HStack(spacing: 2) {
                ForEach(Array(visibleSections.enumerated()), id: \.element) { idx, section in
                    sectionLabel(section).frame(width: sectionExtent(section))
                    if idx < visibleSections.count - 1 {
                        Color.clear.frame(width: 1)
                    }
                }
            }
            .padding(.horizontal, Design.Spacing.toolbarPadding)
        }
    }

    private var verticalContent: some View {
        HStack(spacing: 2) {
            VStack(spacing: 2) {
                ForEach(Array(visibleSections.enumerated()), id: \.element) { idx, section in
                    VStack(spacing: 2) { sectionContent(section) }
                    if idx < visibleSections.count - 1 { dividerView }
                }
            }
            .padding(Design.Spacing.toolbarPadding)
            .background(barBackground)

            VStack(spacing: 2) {
                ForEach(Array(visibleSections.enumerated()), id: \.element) { idx, section in
                    sectionLabel(section)
                        .frame(height: sectionExtent(section))
                    if idx < visibleSections.count - 1 {
                        Color.clear.frame(height: 1)
                    }
                }
            }
            .padding(.vertical, Design.Spacing.toolbarPadding)
        }
    }

    private func sectionLabel(_ section: ToolbarSection) -> some View {
        Text(section.displayName)
            .font(.system(size: 10, weight: .light))
            .foregroundStyle(.secondary)
            .fixedSize()
    }

    private var barBackground: some View {
        RoundedRectangle(cornerRadius: Design.CornerRadius.toolbar)
            .fill(Color("ToolbarBackground"))
            .shadow(
                color: .black.opacity(Design.Shadow.toolbar.color),
                radius: Design.Shadow.toolbar.radius,
                x: Design.Shadow.toolbar.x,
                y: Design.Shadow.toolbar.y
            )
    }

    @ViewBuilder
    private var dividerView: some View {
        if positioning.axis == .horizontal {
            Divider().frame(height: Design.Layout.headerButtonSize)
        } else {
            Divider().frame(width: Design.Layout.headerButtonSize)
        }
    }

    private func sectionHasContent(_ section: ToolbarSection) -> Bool {
        switch section {
        case .undoRedo: return toolbar.showUndoRedo
        case .tools: return !toolIcons.isEmpty
        case .colors: return !colorIcons.isEmpty
        }
    }

    @ViewBuilder
    private func sectionContent(_ section: ToolbarSection) -> some View {
        let sectionLifted = toolbar.previewDraggedSection == section
        switch section {
        case .undoRedo:
            staticIcon("arrow.uturn.backward").modifier(LiftedModifier(lifted: sectionLifted))
            staticIcon("arrow.uturn.forward").modifier(LiftedModifier(lifted: sectionLifted))
        case .tools:
            ForEach(toolIcons) { icon in
                cell(icon: icon)
                    .modifier(LiftedModifier(lifted: sectionLifted || toolbar.previewDraggedIconID == icon.id))
            }
        case .colors:
            ForEach(colorIcons) { icon in
                cell(icon: icon)
                    .modifier(LiftedModifier(lifted: sectionLifted || toolbar.previewDraggedIconID == icon.id))
            }
        }
    }

    private func staticIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: Design.FontSize.toolIcon))
            .foregroundStyle(.secondary)
            .frame(width: ToolbarConstants.tapTargetSize, height: ToolbarConstants.tapTargetSize)
    }

    private func cell(icon: ToolbarIcon) -> some View {
        Group {
            if icon.type == .color, let color = icon.color {
                ColorSwatchView(color: color, showCheckmark: false)
            } else {
                Image(systemName: icon.type.iconName)
                    .font(.system(size: Design.FontSize.toolIcon))
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: ToolbarConstants.tapTargetSize, height: ToolbarConstants.tapTargetSize)
    }
}

private struct LiftedModifier: ViewModifier {
    let lifted: Bool
    func body(content: Content) -> some View {
        content
            .scaleEffect(lifted ? 1.15 : 1.0)
            .offset(y: lifted ? -4 : 0)
            .shadow(color: lifted ? .black.opacity(0.25) : .clear, radius: 6, y: 3)
            .zIndex(lifted ? 10 : 0)
    }
}
