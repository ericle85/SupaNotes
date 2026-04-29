import CoreGraphics

// MARK: - Page Layout Math

/// Pure math helpers for page positions and scroll sizing.
enum PageLayout {
    /// Calculate the container width needed to hold pages with side gaps. Containers hold the pages themselves.
    /// The container must be at least as wide as the scroll view.
    static func containerWidth(pageW: CGFloat, gap: CGFloat, scrollWidth: CGFloat) -> CGFloat {
        // Ensure container is wide enough for page plus side gaps, or scroll view width.
        max(pageW + gap * 2, scrollWidth)
    }

    /// Container width for variable-size pages — uses the widest page.
    static func containerWidth(pageSizes: [CGSize], gap: CGFloat, scrollWidth: CGFloat) -> CGFloat {
        let maxWidth = pageSizes.map(\.width).max() ?? PageConstants.pageWidth
        return containerWidth(pageW: maxWidth, gap: gap, scrollWidth: scrollWidth)
    }

    /// Calculate the frame for a single page at a given index (uniform size).
    static func pageFrame(index: Int, pageW: CGFloat, pageH: CGFloat, gap: CGFloat, containerWidth: CGFloat) -> CGRect {
        CGRect(
            x: (containerWidth - pageW) / 2, // Center the page horizontally in the container.
            y: gap + CGFloat(index) * (pageH + gap), // Stack pages vertically with gaps between them.
            width: pageW,
            height: pageH
        )
    }

    /// Calculate frames for all pages in the document (uniform size).
    static func pageFrames(count: Int, pageW: CGFloat, pageH: CGFloat, gap: CGFloat, containerWidth: CGFloat) -> [CGRect] {
        // Generate a frame for each page index.
        (0 ..< count).map {
            pageFrame(index: $0, pageW: pageW, pageH: pageH, gap: gap, containerWidth: containerWidth)
        }
    }

    /// Calculate frames for variable-size pages, stacking vertically with gaps.
    static func pageFrames(pageSizes: [CGSize], gap: CGFloat, containerWidth: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var y = gap // Start after the top gap.
        for size in pageSizes {
            let x = (containerWidth - size.width) / 2 // Center each page horizontally.
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            y += size.height + gap
        }
        return frames
    }

    /// Total container height for variable-size pages.
    static func containerHeight(pageSizes: [CGSize], gap: CGFloat) -> CGFloat {
        let totalPageHeight = pageSizes.map(\.height).reduce(0, +)
        // Top gap + pages + gaps between pages + bottom gap.
        return gap + totalPageHeight + CGFloat(max(0, pageSizes.count - 1)) * gap + gap
    }

    /// Center content when it is smaller than the visible scroll area.
    static func centeringOrigin(contentSize: CGSize, scrollBounds: CGSize) -> CGPoint {
        // Subtracting content width from scroll area width gives the total leftover horizontal space.
        // Dividing by 2 splits it equally on both sides, so the content sits in the middle.
        // max(0, ...) clamps to zero — if the content is wider than the scroll area, don't offset at all.
        CGPoint(
            x: max(0, (scrollBounds.width - contentSize.width) / 2),
            y: max(0, (scrollBounds.height - contentSize.height) / 2)
        )
    }

    /// Expected scrollable content size after zoom is applied.
    static func scrollContentSize(containerSize: CGSize, zoomScale: CGFloat) -> CGSize {
        CGSize(width: containerSize.width * zoomScale, height: containerSize.height * zoomScale) // Scale both dimensions by the zoom factor.
    }
}
