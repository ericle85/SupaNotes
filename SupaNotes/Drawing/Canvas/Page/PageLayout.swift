import CoreGraphics

// MARK: - Viewport State

/// Saved scroll position + zoom for restoring after a page rebuild.
struct ViewportState {
    let pageIndex: Int
    let pageAnchor: CGPoint
    let anchorInScrollView: CGPoint
    let zoomScale: CGFloat
}

// MARK: - Page Layout Math

/// Pure geometry helpers — no UIKit. Takes sizes/offsets in, returns frames/offsets out.
enum PageLayout {

    // MARK: Container sizing

    /// Canvas width for variable-size pages — uses the widest page plus side margins, floored at scroll view width.
    static func getCanvasWidth(pageSizes: [CGSize], gap: CGFloat, scrollWidth: CGFloat) -> CGFloat {
        let maxWidth = pageSizes.map(\.width).max() ?? PageConstants.pageWidth
        return max(maxWidth + gap * 2, scrollWidth)
    }

    /// Total container height for variable-size pages.
    static func getContainerHeight(pageSizes: [CGSize], gap: CGFloat) -> CGFloat {
        let totalPageHeight = pageSizes.map(\.height).reduce(0, +)
        return gap + totalPageHeight + CGFloat(max(0, pageSizes.count - 1)) * gap + gap
    }

    // MARK: Page frames

    /// Frames for variable-size pages, stacked vertically with gaps.
    static func getPageFramesAsCGRects(pageSizes: [CGSize], gap: CGFloat, containerWidth: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var y = gap
        for size in pageSizes {
            frames.append(CGRect(x: (containerWidth - size.width) / 2, y: y, width: size.width, height: size.height))
            y += size.height + gap
        }
        return frames
    }

    // MARK: Scroll helpers

    /// Expected scrollable content size after zoom.
    static func getScrollContentSize(containerSize: CGSize, zoomScale: CGFloat) -> CGSize {
        CGSize(width: containerSize.width * zoomScale, height: containerSize.height * zoomScale)
    }

    /// Origin that centers content when it is smaller than the visible scroll area.
    static func getCenteringOrigin(contentSize: CGSize, scrollBounds: CGSize) -> CGPoint {
        CGPoint(
            x: max(0, (scrollBounds.width - contentSize.width) / 2),
            y: max(0, (scrollBounds.height - contentSize.height) / 2)
        )
    }

    /// Clamp a content offset to valid scroll bounds.
    static func getClampedOffset(_ offset: CGPoint, contentSize: CGSize, boundsSize: CGSize) -> CGPoint {
        let maxX = max(0, contentSize.width - boundsSize.width)
        let maxY = max(0, contentSize.height - boundsSize.height)
        return CGPoint(x: min(max(0, offset.x), maxX), y: min(max(0, offset.y), maxY))
    }

    // MARK: Current page

    /// Index of the page closest to a given vertical center (in container coords).
    static func getCurrentPageIndex(centerY: CGFloat, pageFrames: [CGRect]) -> Int {
        pageFrames.enumerated().min { lhs, rhs in
            abs(lhs.element.midY - centerY) < abs(rhs.element.midY - centerY)
        }?.offset ?? 0
    }

    // MARK: Viewport capture / restore

    /// Capture viewport as a pure function of scroll geometry.
    static func captureViewport(
        scrollOffset: CGPoint,
        scrollBoundsSize: CGSize,
        containerOrigin: CGPoint,
        zoomScale: CGFloat,
        pageFrames: [CGRect],
        anchor: CGPoint? = nil,
        allowOutsidePageAnchor: Bool = false
    ) -> ViewportState? {
        guard !pageFrames.isEmpty else { return nil }
        let zoom = max(zoomScale, 0.001)
        let anchorPt = anchor ?? CGPoint(x: scrollBoundsSize.width / 2, y: scrollBoundsSize.height / 2)
        let inContent = CGPoint(x: scrollOffset.x + anchorPt.x, y: scrollOffset.y + anchorPt.y)
        let inContainer = CGPoint(
            x: (inContent.x - containerOrigin.x) / zoom,
            y: (inContent.y - containerOrigin.y) / zoom
        )
        let pageIndex = pageFrames.enumerated().min { lhs, rhs in
            distanceSquared(inContainer, frame: lhs.element) < distanceSquared(inContainer, frame: rhs.element)
        }?.offset ?? 0
        let frame = pageFrames[pageIndex]
        let pageAnchor = CGPoint(
            x: allowOutsidePageAnchor ? inContainer.x - frame.minX : frame.width / 2,
            y: allowOutsidePageAnchor ? inContainer.y - frame.minY : min(max(0, inContainer.y - frame.minY), frame.height)
        )
        return ViewportState(pageIndex: pageIndex, pageAnchor: pageAnchor, anchorInScrollView: anchorPt, zoomScale: zoom)
    }

    /// Compute the content offset that restores a saved viewport.
    static func getViewportRestorationOffset(
        viewport: ViewportState,
        containerOrigin: CGPoint,
        pageFrames: [CGRect]
    ) -> CGPoint? {
        let zoom = min(Design.Zoom.max, max(Design.Zoom.min, viewport.zoomScale))
        guard viewport.pageIndex < pageFrames.count else { return nil }
        let pf = pageFrames[viewport.pageIndex]
        return CGPoint(
            x: containerOrigin.x + (pf.minX + viewport.pageAnchor.x) * zoom - viewport.anchorInScrollView.x,
            y: containerOrigin.y + (pf.minY + viewport.pageAnchor.y) * zoom - viewport.anchorInScrollView.y
        )
    }

    // MARK: Coordinate conversion

    /// Convert a point from view coordinates to page (letter) coordinates.
    /// Maps proportionally — e.g. the center of the view becomes the center of the page.
    static func toLetterSpace(_ point: CGPoint, viewSize: CGSize, pageSize: CGSize) -> CGPoint {
        let relativeX = viewSize.width > 0 ? point.x / viewSize.width : 0
        let relativeY = viewSize.height > 0 ? point.y / viewSize.height : 0
        return CGPoint(x: relativeX * pageSize.width, y: relativeY * pageSize.height)
    }

    // MARK: Private

    /// Squared distance from point to rect (0 if inside).
    private static func distanceSquared(_ point: CGPoint, frame: CGRect) -> CGFloat {
        let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
        let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
        return dx * dx + dy * dy
    }
}
