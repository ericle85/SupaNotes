import Foundation

enum Design {
    // MARK: - Layout
    enum Layout {
        static let sidebarWidth: CGFloat = 260
        static let headerButtonSize: CGFloat = 36
        static let floatingButtonSize: CGFloat = 40
        static let sidebarIconWidth: CGFloat = 24
        static let colorSwatchSize: CGFloat = 24
        static let colorSwatchLargeSize: CGFloat = 44
        static let plusButtonSize: CGFloat = 26
    }

    // MARK: - Zoom
    enum Zoom {
        static let min: CGFloat = 0.125
        static let max: CGFloat = 0.75
    }

    // MARK: - Pull to Add
    enum PullToAdd {
        /// How far you drag before the indicator starts filling up
        static let activationThreshold: CGFloat = 80
        /// How far you drag to actually add a new page
        static let triggerThreshold: CGFloat = 200
        /// Minimum drag before the indicator appears at all
        static let showThreshold: CGFloat = 10
        /// Width of the indicator area
        static let indicatorWidth: CGFloat = 150
        /// Height of the indicator area
        static let indicatorHeight: CGFloat = 100
    }

    // MARK: - Corner Radii
    enum CornerRadius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 10
        static let toolbar: CGFloat = 12
    }

    // MARK: - Shadow
    struct Shadow {
        let color: CGFloat // opacity
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat

        static let toolbar = Shadow(color: 0.15, radius: 8, x: 0, y: 2)
        static let floating = Shadow(color: 0.1, radius: 4, x: 0, y: 2)
        static let subtle = Shadow(color: 0.08, radius: 4, x: 0, y: 1)
        static let page = Shadow(color: 0.08, radius: 8, x: 0, y: 2)
    }

    // MARK: - Animation
    enum Animation {
        static let sidebarDuration: Double = 0.25
        static let springResponse: Double = 0.35
        static let springDamping: Double = 0.8
    }

    // MARK: - Spacing
    enum Spacing {
        static let toolbarPadding: CGFloat = 8
        static let toolbarEdgePadding: CGFloat = 18
        static let headerHorizontal: CGFloat = 16
        static let headerVertical: CGFloat = 10
        static let pageCounterLeading: CGFloat = 20
        static let pageCounterBottom: CGFloat = 20
    }

    // MARK: - Font Sizes
    enum FontSize {
        static let headerIcon: CGFloat = 18
        static let toolIcon: CGFloat = 16
        static let plusIcon: CGFloat = 14
    }

    // MARK: - Drag
    enum Drag {
        static let deleteThreshold: CGFloat = 50
        static let reorderMinDistance: CGFloat = 2
        static let tapMaxDistance: CGFloat = 5
        static let repositionDelay: Double = 0.15
        static let toolbarMinDragDistance: CGFloat = 15
    }

    // MARK: - Slider Ranges
    enum SliderRange {
        static let pen: ClosedRange<CGFloat> = 1...50
        static let eraser: ClosedRange<CGFloat> = 10...150
        static let highlighter: ClosedRange<CGFloat> = 5...40
    }

    // MARK: - Debounce
    enum Debounce {
        static let drawingSave: Double = 0.3
        static let pullReset: Double = 0.3
    }
}
