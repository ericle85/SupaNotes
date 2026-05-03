import UIKit

// MARK: - Canvas Lifecycle
//
// Manages the 3-tier rendering system:
//   Tier 1 — LIVE canvases:     interactive, accept Apple Pencil (visible pages)
//   Tier 2 — ADJACENT canvases: display-only, vector-sharp (±1 from visible)
//   Tier 3 — BITMAPS:           lightweight raster snapshots (everything else)
//
// Reading order:
//   1. Visible page detection — which pages are on screen
//   2. Mount/unmount primitives — single-page tier transitions
//   3. Reconciliation — syncs all tiers with scroll position
//   4. Teardown — full cleanup before rebuild

extension MultipageCanvasContainer.Coordinator {

    // MARK: Visible Page Detection

    // Returns which page indices are currently visible in the scroll viewport.
    func visiblePageIndices() -> Set<Int> {
        guard let scrollView, let containerView, !pageFrames.isEmpty else { return [] }
        let visibleRect = scrollView.convert(scrollView.bounds, to: containerView)
        var result = Set<Int>()
        for (i, frame) in pageFrames.enumerated() {
            if frame.intersects(visibleRect) { result.insert(i) }
        }
        return result
    }

    // Which page is centered in the viewport.
    func currentPageIndex() -> Int {
        guard let scrollView, let containerView, !pageFrames.isEmpty else { return 0 }
        let centerY = (scrollView.contentOffset.y + scrollView.bounds.height / 2)
            / max(scrollView.zoomScale, 0.001) - containerView.frame.minY
        let raw = PageLayout.getCurrentPageIndex(centerY: centerY, pageFrames: pageFrames)
        return min(raw, max(0, sortedPages.count - 1))
    }

    // MARK: Mount Primitives

    // Mount a new Tier-1 (live) canvas on a page slot.
    func mountLiveCanvas(on index: Int) {
        guard index >= 0, index < sortedPages.count, index < slots.count else { return }
        let page = sortedPages[index]
        let frame = CGRect(origin: .zero, size: pageFrames[index].size)
        let style = ToolStyle.from(toolbar: toolbar)
        let canvas = DrawingCanvasView(page: page, frame: frame, toolStyle: style, onPageMutated: onPageMutated)
        canvas.interactionDelegate = self

        // Clear the bitmap — the live canvas replaces it visually.
        slots[index].bitmap = nil
        slots[index].addSubview(canvas)

        // Set zoom AFTER addSubview so the view has a window and correct screen scale.
        canvas.updateZoomScale(scrollView?.zoomScale ?? 1.0)
        liveCanvases[index] = canvas
    }

    // Remove a Tier-1 (live) canvas. Optionally flushes strokes to the model first.
    // Falls back to a Tier-3 bitmap after removal.
    func unmountLiveCanvas(at index: Int, flushToModel: Bool) {
        guard let canvas = liveCanvases.removeValue(forKey: index) else { return }
        if flushToModel { canvas.flushToModel() }
        snapshotPageToBitmap(at: index)
        canvas.removeFromSuperview()
    }

    // Mount a new Tier-2 (adjacent/display-only) canvas on a page slot.
    func mountAdjacentCanvas(at index: Int) {
        guard index >= 0, index < sortedPages.count, index < slots.count else { return }
        let page = sortedPages[index]
        let frame = CGRect(origin: .zero, size: pageFrames[index].size)
        let style = ToolStyle.from(toolbar: toolbar)
        let canvas = DrawingCanvasView(page: page, frame: frame, toolStyle: style, onPageMutated: onPageMutated)
        // Display-only: no pencil input, only visual.
        canvas.isUserInteractionEnabled = false
        slots[index].bitmap = nil
        slots[index].addSubview(canvas)
        canvas.updateZoomScale(scrollView?.zoomScale ?? 1.0)
        adjacentCanvases[index] = canvas
    }

    // Remove a Tier-2 (adjacent) canvas. Falls back to a Tier-3 bitmap.
    func unmountAdjacentCanvas(at index: Int) {
        guard let canvas = adjacentCanvases.removeValue(forKey: index) else { return }
        snapshotPageToBitmap(at: index)
        canvas.removeFromSuperview()
    }

    // Render a Tier-3 bitmap snapshot for a page slot.
    func snapshotPageToBitmap(at index: Int) {
        guard index >= 0, index < slots.count, index < sortedPages.count else { return }
        slots[index].bitmap = PageBitmapRenderer.render(page: sortedPages[index])
    }

    // MARK: Reconciliation
    //
    // "reconcile" = full pass (mount + unmount). "evict" = unmount only (cheaper, used mid-scroll).

    // Full reconciliation: ask CanvasTierManager for the target state,
    // then diff against current mounts and execute transitions.
    func reconcileLiveCanvases() {
        let visible = visiblePageIndices()
        // Short-circuit if visible set hasn't changed since last reconcile.
        guard visible != lastReconciledVisible else { return }
        lastReconciledVisible = visible

        let assignment = CanvasTierManager.assignTiers(visible: visible, pageCount: sortedPages.count)

        // Unmount live canvases that are no longer in the live set.
        for index in Set(liveCanvases.keys).subtracting(assignment.live) {
            unmountLiveCanvas(at: index, flushToModel: true)
        }

        // Mount new live canvases where needed.
        for index in assignment.live.subtracting(Set(liveCanvases.keys)) {
            // If an adjacent canvas exists here, remove it — this page is now live.
            if let adj = adjacentCanvases.removeValue(forKey: index) {
                adj.removeFromSuperview()
            }
            mountLiveCanvas(on: index)
        }
    }

    // Mount/unmount adjacent canvases to match CanvasTierManager's assignment.
    func mountAdjacentCanvases() {
        let visible = visiblePageIndices()
        let assignment = CanvasTierManager.assignTiers(visible: visible, pageCount: sortedPages.count)

        // Remove canvases that are no longer adjacent.
        for index in adjacentCanvases.keys where !assignment.adjacent.contains(index) {
            unmountAdjacentCanvas(at: index)
        }
        // Mount new adjacent canvases where needed.
        for index in assignment.adjacent where adjacentCanvases[index] == nil {
            mountAdjacentCanvas(at: index)
        }
    }

    // Render bitmaps for any visible slots that don't already have a canvas or bitmap.
    func fillVisibleBitmaps() {
        guard let scrollView, let containerView else { return }
        let visibleRect = scrollView.convert(scrollView.bounds, to: containerView)
        let liveIndices = Set(liveCanvases.keys)
        for (i, slot) in slots.enumerated() {
            guard !liveIndices.contains(i), slot.bitmap == nil, slot.frame.intersects(visibleRect) else { continue }
            slot.bitmap = PageBitmapRenderer.render(page: sortedPages[i])
        }
    }

    // Evict off-screen canvases during scroll (cheap — no new mounts, just teardown).
    // Mounting new canvases waits for scroll to settle (see handleScrollSettle).
    func evictOffScreenCanvases() {
        let visible = visiblePageIndices()
        let plan = CanvasTierManager.evictionTargets(
            visible: visible,
            mountedLive: Set(liveCanvases.keys),
            mountedAdjacent: Set(adjacentCanvases.keys)
        )

        // Invalidate reconciliation cache if any live canvas is being evicted,
        // so the next full reconcile (on settle) runs fresh.
        if !plan.live.isEmpty { lastReconciledVisible = [] }

        for index in plan.live {
            unmountLiveCanvas(at: index, flushToModel: true)
        }
        for index in plan.adjacent {
            unmountAdjacentCanvas(at: index)
        }
    }

    // MARK: Teardown

    // Remove all canvases and slots (used before a full rebuild).
    func tearDown() {
        for index in Array(adjacentCanvases.keys) { unmountAdjacentCanvas(at: index) }
        for (_, canvas) in liveCanvases {
            canvas.flushToModel()
            canvas.removeFromSuperview()
        }
        liveCanvases.removeAll()
        lastReconciledVisible = []
        for slot in slots { slot.removeFromSuperview() }
        slots.removeAll()
        sortedPages = []
        pageFrames = []
    }

    // Force the next reconcile to run fresh instead of short-circuiting.
    func invalidateReconciliationCache() {
        lastReconciledVisible = []
    }
}
