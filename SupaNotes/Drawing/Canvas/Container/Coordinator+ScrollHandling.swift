import UIKit

// MARK: - Scroll Handling
//
// UIScrollViewDelegate + scroll-to-page + viewport capture/restore.
//
// During scroll: evict off-screen canvases, fill bitmap gaps (cheap).
// On scroll settle: full reconciliation across all 3 canvas tiers.

extension MultipageCanvasContainer.Coordinator {

    // MARK: UIScrollViewDelegate

    func viewForZooming(in _: UIScrollView) -> UIView? {
        containerView
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        pullController.update(for: scrollView)
        // Mid-scroll: only evict and fill bitmaps. No new canvas mounts until settle.
        evictOffScreenCanvases()
        fillVisibleBitmaps()
    }

    func scrollViewDidZoom(_: UIScrollView) {
        centerContainerIfNeeded()
    }

    func scrollViewDidEndZooming(_: UIScrollView, with _: UIView?, atScale scale: CGFloat) {
        liveCanvases.values.forEach { $0.updateZoomScale(scale) }
        adjacentCanvases.values.forEach { $0.updateZoomScale(scale) }
    }

    func scrollViewDidEndDragging(_: UIScrollView, willDecelerate decelerate: Bool) {
        let scroll = pullController.handleEndDragging(addPage: addPage, addPageAbove: addPageAbove)
        if scroll != .none { pendingScroll = scroll }
        if !decelerate { handleScrollSettle() }
    }

    func scrollViewDidEndDecelerating(_: UIScrollView) {
        handleScrollSettle()
    }

    // MARK: Scroll Settle

    // Called when scrolling stops (drag end without deceleration, or deceleration end).
    // Does a full reconciliation across all 3 tiers.
    func handleScrollSettle() {
        // Report which page is centered.
        let index = currentPageIndex()
        onCurrentPageChanged?(index)
        if let canvas = liveCanvases[index] {
            onUndoManagerReady(canvas.undoManagerForPage)
        }

        // Force a fresh reconcile pass (not short-circuited).
        invalidateReconciliationCache()
        reconcileLiveCanvases()
        fillVisibleBitmaps()
        mountAdjacentCanvases()

        // Update zoom scale on all canvases.
        let zoom = scrollView?.zoomScale ?? 1.0
        liveCanvases.values.forEach { $0.updateZoomScale(zoom) }

        // Clear bitmaps that are off-screen and outside the live + adjacent range.
        let canvasIndices = Set(liveCanvases.keys).union(adjacentCanvases.keys)
        let visible = visiblePageIndices()
        let toClear = CanvasTierManager.bitmapsToClear(
            visible: visible, canvasIndices: canvasIndices,
            slotCount: slots.count, hasBitmap: { slots[$0].bitmap != nil }
        )
        for i in toClear { slots[i].bitmap = nil }
    }

    // MARK: Scroll-to-Page

    func scrollToPage(index: Int) {
        guard let scrollView, let containerView, index < pages.count, index < pageFrames.count else { return }
        scrollView.zoomScale = 1.0
        scrollView.contentSize = PageLayout.getScrollContentSize(containerSize: containerView.bounds.size, zoomScale: 1.0)
        centerContainerIfNeeded()
        let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        let targetY = min(max(0, containerView.frame.minY + pageFrames[index].minY - 20), maxY)
        UIView.animate(withDuration: 0.3) {
            scrollView.contentOffset = CGPoint(x: 0, y: targetY)
        } completion: { [weak self] _ in
            self?.handleScrollSettle()
        }
    }

    func applyPendingScroll(frames: [CGRect]) {
        guard let scrollView, let containerView else { return }
        let action = pendingScroll
        pendingScroll = .none
        guard action != .none else { return }

        let preservedX = min(max(0, scrollView.contentOffset.x), max(0, scrollView.contentSize.width - scrollView.bounds.width))
        let target: CGPoint
        switch action {
        case .none: return
        case .scrollToFirst:
            target = CGPoint(x: preservedX, y: 0)
        case .scrollToLast:
            guard let last = frames.last else { return }
            let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
            target = CGPoint(x: preservedX, y: min(max(0, containerView.frame.minY + last.minY * scrollView.zoomScale - 20), maxY))
        }
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) { scrollView.contentOffset = target }
    }

    // MARK: Viewport

    func captureViewport() -> ViewportState? {
        guard let scrollView, let containerView, !pages.isEmpty else { return nil }
        return PageLayout.captureViewport(
            scrollOffset: scrollView.contentOffset,
            scrollBoundsSize: scrollView.bounds.size,
            containerOrigin: containerView.frame.origin,
            zoomScale: scrollView.zoomScale,
            pageFrames: pageFrames
        )
    }

    func restoreViewport(_ viewport: ViewportState, containerSize: CGSize, frames: [CGRect]) {
        guard let scrollView, let containerView else { return }
        let zoom = min(Design.Zoom.max, max(Design.Zoom.min, viewport.zoomScale))
        scrollView.zoomScale = zoom
        scrollView.contentSize = PageLayout.getScrollContentSize(containerSize: containerSize, zoomScale: zoom)
        centerContainerIfNeeded()
        guard let target = PageLayout.getViewportRestorationOffset(
            viewport: viewport, containerOrigin: containerView.frame.origin, pageFrames: frames
        ) else { return }
        scrollView.contentOffset = PageLayout.getClampedOffset(target, contentSize: scrollView.contentSize, boundsSize: scrollView.bounds.size)
    }

    func centerContainerIfNeeded() {
        guard let scrollView, let containerView else { return }
        containerView.frame.origin = PageLayout.getCenteringOrigin(
            contentSize: containerView.frame.size, scrollBounds: scrollView.bounds.size
        )
    }
}
