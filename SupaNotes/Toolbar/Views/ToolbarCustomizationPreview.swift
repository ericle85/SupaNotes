import SwiftUI

struct ToolbarCustomizationPreview: View {
    @Bindable var toolbar: ToolbarState
    @State private var positioning = ToolbarPositioning()

    @State private var intrinsicSize: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let scale = fitScale(intrinsic: intrinsicSize, available: geo.size)
            Group {
                if positioning.axis == .horizontal {
                    horizontalContent
                } else {
                    verticalContent
                }
            }
            .fixedSize()
            .background(
                GeometryReader { inner in
                    Color.clear.preference(key: PreviewSizeKey.self, value: inner.size)
                }
            )
            .scaleEffect(scale, anchor: .center)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onPreferenceChange(PreviewSizeKey.self) { intrinsicSize = $0 }
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: toolbar.toolbarIcons.map(\.id))
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: toolbar.showUndoRedo)
    }

    private func fitScale(intrinsic: CGSize, available: CGSize) -> CGFloat {
        // If the toolbar has no measured size yet, don't scale at all.
        guard intrinsic.width > 0, intrinsic.height > 0 else { return 1 }
        // How many times does the available width fit into the toolbar's natural width?
        // A value less than 1 means the toolbar is wider than the space — we need to shrink.
        let sx = available.width / intrinsic.width
        // Same check for height.
        let sy = available.height / intrinsic.height
        // Use whichever axis requires the most shrinking so the toolbar fits in both dimensions.
        // Cap at 1 so we never scale UP — only shrink when needed.
        return min(1, min(sx, sy))
    }

    private var visibleSections: [ToolbarSection] {
        toolbar.sectionOrder.filter { sectionHasContent($0) }
    }

    private func iconCount(_ section: ToolbarSection) -> Int {
        switch section {
        case .undoRedo: return 2
        case .tools: return toolbar.toolIcons.count
        case .colors: return toolbar.colorIcons.count
        }
    }

    private func sectionExtent(_ section: ToolbarSection) -> CGFloat {
        let n = iconCount(section)
        return CGFloat(n) * ToolbarConstants.tapTargetSize + CGFloat(max(0, n - 1)) * 2
    }

    private var horizontalContent: some View {
        HStack(spacing: 2) {
            ForEach(Array(visibleSections.enumerated()), id: \.element) { idx, section in
                HStack(spacing: 2) { sectionContent(section) }
                if idx < visibleSections.count - 1 { dividerView }
            }
            // Settings cog matches the live toolbar
            cogIcon
        }
        .padding(Design.Spacing.toolbarPadding)
        .background(barBackground)
    }

    private var verticalContent: some View {
        VStack(spacing: 2) {
            ForEach(Array(visibleSections.enumerated()), id: \.element) { idx, section in
                VStack(spacing: 2) { sectionContent(section) }
                if idx < visibleSections.count - 1 { dividerView }
            }
            // Settings cog matches the live toolbar
            cogIcon
        }
        .padding(Design.Spacing.toolbarPadding)
        .background(barBackground)
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
                color: .black.opacity(Design.Shadow.toolbar.opacity),
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
        case .tools: return !toolbar.toolIcons.isEmpty
        case .colors: return !toolbar.colorIcons.isEmpty
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
            ForEach(toolbar.toolIcons) { icon in
                cell(icon: icon)
                    .modifier(LiftedModifier(lifted: sectionLifted || toolbar.previewDraggedIconID == icon.id))
            }
        case .colors:
            ForEach(toolbar.colorIcons) { icon in
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

    // Mirrors the gear button shown in the live DrawingToolbar
    private var cogIcon: some View {
        ZStack {
            Circle()
                .fill(Color.secondary.opacity(0.15))
                .frame(width: Design.Layout.plusButtonSize, height: Design.Layout.plusButtonSize)
            Image(systemName: "gearshape.fill")
                .font(.system(size: Design.FontSize.plusIcon, weight: .bold))
                .foregroundStyle(.primary)
        }
        .overlay {
            Circle().stroke(Color.primary.opacity(0.3), lineWidth: 1)
        }
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
        .transition(.scale.combined(with: .opacity))
    }
}

private struct PreviewSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
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
