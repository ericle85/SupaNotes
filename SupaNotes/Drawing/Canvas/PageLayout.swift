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

    /// Calculate the frame for a single page at a given index.
    static func pageFrame(index: Int, pageW: CGFloat, pageH: CGFloat, gap: CGFloat, containerWidth: CGFloat) -> CGRect {
        CGRect(
            x: (containerWidth - pageW) / 2, // Center the page horizontally in the container.
            y: gap + CGFloat(index) * (pageH + gap), // Stack pages vertically with gaps between them.
            width: pageW,
            height: pageH
        )
    }

    /// Calculate frames for all pages in the document.
    static func pageFrames(count: Int, pageW: CGFloat, pageH: CGFloat, gap: CGFloat, containerWidth: CGFloat) -> [CGRect] {
        // Generate a frame for each page index.
        (0 ..< count).map {
            pageFrame(index: $0, pageW: pageW, pageH: pageH, gap: gap, containerWidth: containerWidth)
        }
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
