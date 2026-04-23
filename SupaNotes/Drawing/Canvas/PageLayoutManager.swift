import UIKit

// MARK: - Page Layout Manager

/// Owns geometry + page view rebuild logic for the multipage canvas.
final class PageLayoutManager {
    /// Saved viewport state for restoring after rebuild.
    struct ViewportState {
        let pageIndex: Int // Index of the page that was visible.
        let pageAnchor: CGPoint // Anchor point within that page (relative to page origin).
        let anchorInScrollView: CGPoint // Anchor point in scroll view coordinates (relative to scroll view bounds).
        let zoomScale: CGFloat // Current zoom level.
    }

    weak var scrollView: UIScrollView? // The scroll view that contains all pages.
    weak var containerView: UIView? // The container view that holds all page canvas views.
    var canvasViews: [ExcalidrawPageCanvasView] = []
    var hasCompletedInitialLayout = false // Tracks whether we've done the initial layout pass.

    private let pageWidth = PageConstants.pageWidth // Standard page width.
    private let pageHeight = PageConstants.pageHeight // Standard page height.
    private let pageGap = PageConstants.pageGap // Gap between pages in the vertical stack.

    /// Rebuild all page views when pages change or need refresh. Page changes include:
    ///     - Adding new pages
    ///     - Removing pages
    ///     - Reordering pages
    ///     - Updating page content
    func rebuildPages(
        pages: [Page],
        toolStyle: ExcalidrawToolStyle,
        interactionDelegate: ExcalidrawPageCanvasInteractionDelegate,
        pullController: PullToAddController,
        pendingScroll: inout MultipageCanvasContainer.ScrollAfterRebuild,
        viewport: ViewportState?,
        onUndoManagerReady: @escaping (UndoManager?) -> Void,
        onPageMutated: @escaping () -> Void
    ) {
        // Need both scroll view and container to do layout.
        guard let containerView, let scrollView else { return }

        // Sort pages by their display order.
        let sortedPages = pages.sorted { $0.orderIndex < $1.orderIndex }
        // Calculate container width based on page size and scroll view width.
        let containerWidth = PageLayout.containerWidth(pageW: pageWidth, gap: pageGap, scrollWidth: scrollView.bounds.width)

        // Calculate total height needed for all pages plus gaps.
        let totalSize = CGSize(
            width: containerWidth,
            height: CGFloat(sortedPages.count) * pageHeight + CGFloat(max(0, sortedPages.count - 1)) * pageGap + pageGap * 2
        )

        // Calculate frame for each page.
        let pageFrames = PageLayout.pageFrames(
            count: sortedPages.count,
            pageW: pageWidth,
            pageH: pageHeight,
            gap: pageGap,
            containerWidth: containerWidth
        )

        // Rebuild views without animation to avoid flicker.
        UIView.performWithoutAnimation {
            canvasViews.forEach { $0.removeFromSuperview() } // Remove old canvas views.
            canvasViews.removeAll()

            // Resize container to fit all pages.
            containerView.bounds.size = totalSize

            // Create new canvas views for each page.
            canvasViews = pageFrames.enumerated().map { index, frame in
                let canvas = Self.makeCanvasView(
                    page: sortedPages[index],
                    index: index,
                    frame: frame,
                    toolStyle: toolStyle,
                    interactionDelegate: interactionDelegate,
                    onPageMutated: onPageMutated
                )
                containerView.addSubview(canvas)
                return canvas
            }

            // Match every page's vector redraw scale to the current notebook zoom immediately after rebuild.
            canvasViews.forEach { $0.updateZoomScale(scrollView.zoomScale) }

            // Either restore saved viewport or set up initial layout.
            if let viewport {
                restoreViewport(viewport, containerSize: totalSize)
            } else {
                scrollView.contentSize = PageLayout.scrollContentSize(containerSize: totalSize, zoomScale: scrollView.zoomScale)
                centerContainerIfNeeded()
            }

            // Force layout to complete immediately.
            containerView.layoutIfNeeded()
            scrollView.layoutIfNeeded()
        }

        // Set up pull-to-add indicators.
        pullController.setupIndicators(in: scrollView)
        // Apply any pending scroll action (e.g., scroll to new page).
        applyPendingScroll(&pendingScroll, pageCount: sortedPages.count)
        centerContainerIfNeeded()

        // Provide the undo manager to the parent once ready.
        if let first = canvasViews.first {
            DispatchQueue.main.async {
                onUndoManagerReady(first.undoManagerForPage)
            }
        }
    }

    /// Restore the viewport to a previously saved state.
    private func restoreViewport(_ viewport: ViewportState, containerSize: CGSize) {
        guard let scrollView, let containerView else { return }

        // Clamp zoom to allowed range.
        let zoomScale = min(Design.Zoom.max, max(Design.Zoom.min, viewport.zoomScale))
        scrollView.zoomScale = zoomScale
        scrollView.contentSize = PageLayout.scrollContentSize(containerSize: containerSize, zoomScale: zoomScale)
        centerContainerIfNeeded()

        // Find the frame for the saved page index.
        let pageFrame = PageLayout.pageFrame(
            index: viewport.pageIndex,
            pageW: pageWidth,
            pageH: pageHeight,
            gap: pageGap,
            containerWidth: containerSize.width
        )
        // Convert page-relative anchor to container-relative.
        let anchorInContainer = CGPoint(
            x: pageFrame.minX + viewport.pageAnchor.x,
            y: pageFrame.minY + viewport.pageAnchor.y
        )
        // Calculate scroll offset that puts the anchor at the saved scroll view position.
        let targetOffset = CGPoint(
            x: containerView.frame.minX + anchorInContainer.x * zoomScale - viewport.anchorInScrollView.x,
            y: containerView.frame.minY + anchorInContainer.y * zoomScale - viewport.anchorInScrollView.y
        )
        // Apply offset, clamped to valid range.
        scrollView.contentOffset = clampedContentOffset(targetOffset)
    }

    /// Clamp scroll offset to valid range (can't scroll past content edges).
    private func clampedContentOffset(_ offset: CGPoint) -> CGPoint {
        guard let scrollView else { return offset }
        // Calculate maximum valid scroll positions.
        let maxX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
        let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        // Clamp both coordinates to valid range.
        return CGPoint(x: min(max(0, offset.x), maxX), y: min(max(0, offset.y), maxY))
    }

    /// Capture the current viewport state so it can be restored later.
    func captureViewportState(
        pages: [Page],
        anchorInScrollView: CGPoint? = nil,
        allowOutsidePageAnchor: Bool = false
    ) -> ViewportState? {
        guard let scrollView, let containerView, !pages.isEmpty else { return nil }

        // Avoid division by zero with minimum zoom.
        let zoomScale = max(scrollView.zoomScale, 0.001)
        // Use provided anchor or default to center of scroll view.
        let anchor = anchorInScrollView ?? CGPoint(x: scrollView.bounds.width / 2, y: scrollView.bounds.height / 2)
        // Convert anchor to scroll content coordinates.
        let anchorInScrollContent = CGPoint(
            x: scrollView.contentOffset.x + anchor.x,
            y: scrollView.contentOffset.y + anchor.y
        )
        // Convert anchor to container coordinates (unzoomed).
        let anchorInContainer = CGPoint(
            x: (anchorInScrollContent.x - containerView.frame.minX) / zoomScale,
            y: (anchorInScrollContent.y - containerView.frame.minY) / zoomScale
        )

        // Calculate frames for all pages.
        let frames = (0 ..< pages.count).map {
            PageLayout.pageFrame(index: $0, pageW: pageWidth, pageH: pageHeight, gap: pageGap, containerWidth: containerView.bounds.width)
        }
        // Find the page closest to the anchor point.
        let pageIndex = frames.enumerated().min { lhs, rhs in
            distanceToFrame(anchorInContainer, frame: lhs.element) < distanceToFrame(anchorInContainer, frame: rhs.element)
        }?.offset ?? 0

        // Calculate anchor position relative to the closest page.
        let frame = frames[pageIndex]
        let pageAnchor = CGPoint(
            x: allowOutsidePageAnchor ? anchorInContainer.x - frame.minX : frame.width / 2,
            y: allowOutsidePageAnchor ? anchorInContainer.y - frame.minY : min(max(0, anchorInContainer.y - frame.minY), frame.height)
        )

        return ViewportState(pageIndex: pageIndex, pageAnchor: pageAnchor, anchorInScrollView: anchor, zoomScale: zoomScale)
    }

    /// Calculate squared distance from a point to a rectangle (0 if inside).
    private func distanceToFrame(_ point: CGPoint, frame: CGRect) -> CGFloat {
        // Distance in X direction (0 if point is within frame horizontally).
        let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
        // Distance in Y direction (0 if point is within frame vertically).
        let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
        // Return squared distance (sqrt not needed for comparison).
        return dx * dx + dy * dy
    }

    /// Create a single canvas view for a page with proper styling.
    private static func makeCanvasView(
        page: Page,
        index: Int,
        frame: CGRect,
        toolStyle: ExcalidrawToolStyle,
        interactionDelegate: ExcalidrawPageCanvasInteractionDelegate,
        onPageMutated: @escaping () -> Void
    ) -> ExcalidrawPageCanvasView {
        // Create the canvas view.
        let canvas = ExcalidrawPageCanvasView(page: page, frame: frame, toolStyle: toolStyle, onPageMutated: onPageMutated)
        // Store index in tag for later lookup.
        canvas.tag = index
        canvas.interactionDelegate = interactionDelegate

        // Add page shadow for depth effect.
        canvas.layer.shadowColor = UIColor.black.cgColor
        canvas.layer.shadowOpacity = Float(Design.Shadow.page.color)
        canvas.layer.shadowOffset = CGSize(width: Design.Shadow.page.x, height: Design.Shadow.page.y)
        canvas.layer.shadowRadius = Design.Shadow.page.radius
        return canvas
    }

    /// Apply any pending scroll action after page rebuild.
    private func applyPendingScroll(_ pendingScroll: inout MultipageCanvasContainer.ScrollAfterRebuild, pageCount: Int) {
        guard let scrollView, let containerView else { return }

        // Take the pending action and reset it.
        let action = pendingScroll
        pendingScroll = .none

        // Preserve the current X scroll position.
        let preservedX = min(
            max(0, scrollView.contentOffset.x),
            max(0, scrollView.contentSize.width - scrollView.bounds.width)
        )

        // Calculate target scroll position based on action.
        let target: CGPoint
        switch action {
        case .none:
            return
        case .scrollToFirst:
            // Scroll to top of document.
            target = CGPoint(x: preservedX, y: 0)
        case .scrollToLast:
            // Scroll to bottom of document (last page).
            let lastPageY = pageGap + CGFloat(pageCount - 1) * (pageHeight + pageGap)
            let targetY = max(0, (containerView.frame.minY + lastPageY) * scrollView.zoomScale - 20)
            let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
            target = CGPoint(x: preservedX, y: min(targetY, maxY))
        }

        // Animate to target position.
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) {
            scrollView.contentOffset = target
        }
    }

    /// Center the container in the scroll view if content is smaller than view.
    func centerContainerIfNeeded() {
        guard let scrollView, let containerView else { return }
        containerView.frame.origin = PageLayout.centeringOrigin(
            contentSize: containerView.frame.size,
            scrollBounds: scrollView.bounds.size
        )
    }

    /// Smoothly scroll to a specific page by index.
    func scrollToPage(index: Int) {
        guard let scrollView, let containerView, canvasViews.indices.contains(index) else { return }

        // Calculate Y position of the target page.
        let y = pageGap + CGFloat(index) * (pageHeight + pageGap)
        let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        let targetY = min(max(0, (containerView.frame.minY + y) * scrollView.zoomScale - 20), maxY)

        // Animate scroll to target.
        UIView.animate(withDuration: 0.3) {
            scrollView.contentOffset = CGPoint(x: 0, y: targetY)
        }
    }

    /// Update the current page index based on scroll position.
    func updateCurrentPage(pages: [Page], onCurrentPageChanged: ((Int) -> Void)?) {
        guard let scrollView, let containerView else { return }

        // Find the Y coordinate at the center of the visible area (unzoomed).
        let centerY = (scrollView.contentOffset.y + scrollView.bounds.height / 2) / max(scrollView.zoomScale, 0.001) - containerView.frame.minY
        let pageIndex = max(0, Int((centerY - pageGap) / (pageHeight + pageGap))) // Convert Y coordinate to page index.

        onCurrentPageChanged?(min(pageIndex, max(0, pages.count - 1))) // Clamp to valid page range and notify callback.
    }
}
