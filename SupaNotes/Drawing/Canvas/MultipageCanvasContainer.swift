import SwiftData
import SwiftUI
import UIKit

// Main container for all pages in a note — a vertically-scrolling, zoomable UIKit scroll view
// bridged into SwiftUI. Apple Pencil draws; fingers scroll and zoom.
//
// Architecture: every VISIBLE page gets a live DrawingCanvasView (accepts pencil input). Pages
// adjacent (±1) to the visible range get display-only canvases. All others are bitmap snapshots.
struct MultipageCanvasContainer: UIViewRepresentable {
    @Binding var pages: [Page]
    var toolbar: ToolbarState
    var onUndoManagerReady: (UndoManager?) -> Void
    var onPencilDoubleTap: (() -> Void)?
    var onCurrentPageChanged: ((Int) -> Void)?
    var addPage: () -> Void
    var addPageAbove: (() -> Void)?
    var onPageMutated: () -> Void

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = UIColor(named: "PaperBackground") ?? UIColor.systemGroupedBackground
        scrollView.showsVerticalScrollIndicator = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = Design.Zoom.min
        scrollView.maximumZoomScale = Design.Zoom.max
        // Only fingers scroll/zoom — Apple Pencil is reserved for drawing.
        scrollView.panGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        scrollView.pinchGestureRecognizer?.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]

        // Invisible wrapper that zooms as a unit.
        let containerView = UIView()
        containerView.tag = 999
        scrollView.addSubview(containerView)

        let coordinator = context.coordinator
        coordinator.scrollView = scrollView
        coordinator.containerView = containerView

        // Apple Pencil barrel double-tap.
        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = coordinator
        scrollView.addInteraction(pencilInteraction)

        coordinator.rebuildPages(pages: pages, toolbar: toolbar, viewport: nil)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        let c = context.coordinator
        c.pages = pages
        c.toolbar = toolbar
        c.onPencilDoubleTap = onPencilDoubleTap
        c.onCurrentPageChanged = onCurrentPageChanged
        c.addPage = addPage
        c.addPageAbove = addPageAbove
        c.onPageMutated = onPageMutated

        // Sync toolbar to all mounted canvases.
        let style = ToolStyle.from(toolbar: toolbar)
        c.liveCanvases.values.forEach { $0.updateToolStyle(style) }
        c.adjacentCanvases.values.forEach { $0.updateToolStyle(style) }

        // Rebuild when pages change (count, identity) or on first real layout.
        let containerWidth = c.containerView?.frame.width ?? 0
        let pageIDs = pages.map(\.persistentModelID)
        let needsRebuild = pageIDs != c.cachedPageIDs
            || (!c.hasCompletedInitialLayout && scrollView.bounds.width > 0 && abs(containerWidth - scrollView.bounds.width) > 1)

        if needsRebuild {
            c.hasCompletedInitialLayout = scrollView.bounds.width > 0
            let viewport = c.captureViewport()
            c.rebuildPages(pages: pages, toolbar: toolbar, viewport: viewport)
        }

        c.centerContainerIfNeeded()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            pages: pages, toolbar: toolbar,
            onUndoManagerReady: onUndoManagerReady, onPencilDoubleTap: onPencilDoubleTap,
            onCurrentPageChanged: onCurrentPageChanged, addPage: addPage,
            addPageAbove: addPageAbove, onPageMutated: onPageMutated
        )
    }

    /// After rebuilding, optionally scroll to first or last page.
    enum ScrollAfterRebuild: Equatable { case none, scrollToFirst, scrollToLast }

    // MARK: - Coordinator

    /// UIKit bridge: owns scroll/zoom delegation, live canvases for visible pages,
    /// page slots, pencil interaction, and pull-to-add.
    final class Coordinator: NSObject, UIScrollViewDelegate, UIPencilInteractionDelegate, DrawingCanvasDelegate {
        // MARK: External state (updated each SwiftUI pass)

        var pages: [Page] {
            didSet {
                let newIDs = pages.map(\.persistentModelID)
                guard newIDs != cachedPageIDs else { return }
                let viewport = captureViewport()
                rebuildPages(pages: pages, toolbar: toolbar, viewport: viewport)
            }
        }

        var toolbar: ToolbarState
        var onUndoManagerReady: (UndoManager?) -> Void
        var onPencilDoubleTap: (() -> Void)?
        var onCurrentPageChanged: ((Int) -> Void)?
        var addPage: () -> Void
        var addPageAbove: (() -> Void)?
        var onPageMutated: () -> Void

        // MARK: UIKit refs

        weak var scrollView: UIScrollView?
        weak var containerView: UIView?

        // MARK: Canvas state

        /// Interactive canvases for all visible pages — each accepts pencil input.
        private(set) var liveCanvases: [Int: DrawingCanvasView] = [:]
        /// Display-only canvases on pages adjacent (±1) to the visible range.
        private(set) var adjacentCanvases: [Int: DrawingCanvasView] = [:]
        /// Cached visible set so reconciliation short-circuits when nothing changed.
        private var lastReconciledVisible: Set<Int> = []
        /// All page slots in order.
        private(set) var slots: [PageSlotView] = []
        // Sorted pages and their frames from the last rebuild.
        private(set) var sortedPages: [Page] = []
        private(set) var pageFrames: [CGRect] = []

        var cachedPageIDs: [PersistentIdentifier] = []
        var hasCompletedInitialLayout = false
        let pullController = PullToAddController()
        var pendingScroll: ScrollAfterRebuild = .none
        /// Test seam + future hook: called when we intentionally stop in-flight scroll motion.
        /// Default is nil so production behavior stays simple.
        var onRequestStopScrollMomentum: ((UIScrollView) -> Void)?

        private let pageGap = PageConstants.pageGap

        // MARK: Init / deinit

        init(
            pages: [Page], toolbar: ToolbarState,
            onUndoManagerReady: @escaping (UndoManager?) -> Void,
            onPencilDoubleTap: (() -> Void)?,
            onCurrentPageChanged: ((Int) -> Void)?,
            addPage: @escaping () -> Void,
            addPageAbove: (() -> Void)?,
            onPageMutated: @escaping () -> Void
        ) {
            self.pages = pages
            self.toolbar = toolbar
            self.onUndoManagerReady = onUndoManagerReady
            self.onPencilDoubleTap = onPencilDoubleTap
            self.onCurrentPageChanged = onCurrentPageChanged
            self.addPage = addPage
            self.addPageAbove = addPageAbove
            self.onPageMutated = onPageMutated
            super.init()

            NotificationCenter.default.addObserver(forName: .scrollToPage, object: nil, queue: .main) { [weak self] note in
                guard let index = note.object as? Int else { return }
                self?.scrollToPage(index: index)
            }
            NotificationCenter.default.addObserver(forName: .flushDrawings, object: nil, queue: .main) { [weak self] _ in
                self?.liveCanvases.values.forEach { $0.flushToModel() }
            }
        }

        deinit { NotificationCenter.default.removeObserver(self) }

        // MARK: Page rebuild

        func rebuildPages(pages: [Page], toolbar _: ToolbarState, viewport: ViewportState?) {
            guard let containerView, let scrollView else { return }

            let sorted = pages.sorted { $0.orderIndex < $1.orderIndex }
            let pageSizes = sorted.map(\.size)
            cachedPageIDs = sorted.map(\.persistentModelID)

            let cw = PageLayout.getCanvasWidth(pageSizes: pageSizes, gap: pageGap, scrollWidth: scrollView.bounds.width)
            let totalHeight = PageLayout.getContainerHeight(pageSizes: pageSizes, gap: pageGap)
            let totalSize = CGSize(width: cw, height: totalHeight)
            let frames = PageLayout.getPageFramesAsCGRects(pageSizes: pageSizes, gap: pageGap, containerWidth: cw)

            UIView.performWithoutAnimation {
                // Tear down existing canvas and slots.
                tearDown()
                containerView.bounds.size = totalSize
                sortedPages = sorted
                pageFrames = frames

                // Create lightweight slots for every page.
                for (i, page) in sorted.enumerated() {
                    let slot = PageSlotView(frame: frames[i], template: page.template)
                    slot.pageIndex = i
                    containerView.addSubview(slot)
                    slots.append(slot)
                }

                // Restore viewport or set initial layout.
                if let viewport {
                    restoreViewport(viewport, containerSize: totalSize, frames: frames)
                } else {
                    scrollView.contentSize = PageLayout.getScrollContentSize(containerSize: totalSize, zoomScale: scrollView.zoomScale)
                    centerContainerIfNeeded()
                }

                containerView.layoutIfNeeded()
                scrollView.layoutIfNeeded()

                // Mount live canvases on all visible pages, then adjacent display canvases.
                reconcileLiveCanvases()
                fillVisibleBitmaps()
                mountAdjacentCanvases()
            }

            pullController.setupIndicators(in: scrollView)
            applyPendingScroll(frames: frames)
            centerContainerIfNeeded()

            // Deliver focused page's undo manager on next run loop.
            let centerIndex = currentPageIndex()
            if let canvas = liveCanvases[centerIndex] {
                DispatchQueue.main.async { [weak self] in self?.onUndoManagerReady(canvas.undoManagerForPage) }
            }
        }

        // MARK: Focus management

        /// Mount a fresh live canvas on the given page index and add it to the liveCanvases dict.
        private func mountCanvas(on index: Int) {
            guard index >= 0, index < sortedPages.count, index < slots.count else { return }
            let page = sortedPages[index]
            let frame = CGRect(origin: .zero, size: pageFrames[index].size)
            let style = ToolStyle.from(toolbar: toolbar)
            let canvas = DrawingCanvasView(page: page, frame: frame, toolStyle: style, onPageMutated: onPageMutated)
            canvas.interactionDelegate = self

            // Hide the slot's bitmap — canvas covers it.
            slots[index].bitmap = nil
            slots[index].addSubview(canvas)

            // Update zoom AFTER addSubview so the view has a window and correct screen scale.
            canvas.updateZoomScale(scrollView?.zoomScale ?? 1.0)

            liveCanvases[index] = canvas
        }

        /// Remove live canvases that have scrolled completely off-screen (teardown only, no mounts).
        private func evictOffScreenCanvases() {
            let visible = visiblePageIndices()
            let hasStale = liveCanvases.keys.contains { !visible.contains($0) }
            if hasStale { lastReconciledVisible = [] }
            for index in liveCanvases.keys where !visible.contains(index) {
                if let canvas = liveCanvases.removeValue(forKey: index) {
                    canvas.flushToModel()
                    if index < slots.count {
                        slots[index].bitmap = PageBitmapRenderer.render(page: sortedPages[index])
                    }
                    canvas.removeFromSuperview()
                }
            }
            // Also evict adjacent canvases that are far from the current visible range.
            for index in adjacentCanvases.keys where !visible.contains(index) {
                guard let minV = visible.min(), let maxV = visible.max() else { break }
                if index < minV - 1 || index > maxV + 1 {
                    if index < slots.count {
                        slots[index].bitmap = PageBitmapRenderer.render(page: sortedPages[index])
                    }
                    adjacentCanvases.removeValue(forKey: index)?.removeFromSuperview()
                }
            }
        }

        /// Page indices whose frames intersect the current viewport.
        private func visiblePageIndices() -> Set<Int> {
            guard let scrollView, let containerView, !pageFrames.isEmpty else { return [] }
            let visibleRect = scrollView.convert(scrollView.bounds, to: containerView)
            var result = Set<Int>()
            for (i, frame) in pageFrames.enumerated() {
                if frame.intersects(visibleRect) { result.insert(i) }
            }
            return result
        }

        /// Reconcile live canvases with the current visible set. Mounts newly visible pages,
        /// tears down pages that scrolled out of view.
        private func reconcileLiveCanvases() {
            let visible = visiblePageIndices()
            guard visible != lastReconciledVisible else { return }
            lastReconciledVisible = visible

            let currentlyMounted = Set(liveCanvases.keys)

            // Teardown canvases that scrolled out of view.
            for index in currentlyMounted.subtracting(visible) {
                if let canvas = liveCanvases.removeValue(forKey: index) {
                    canvas.flushToModel()
                    if index < slots.count {
                        slots[index].bitmap = PageBitmapRenderer.render(page: sortedPages[index])
                    }
                    canvas.removeFromSuperview()
                }
            }

            // Mount canvases for newly visible pages.
            for index in visible.subtracting(currentlyMounted) {
                // Remove adjacent display canvas if one exists here (it's now a live page).
                if let adj = adjacentCanvases.removeValue(forKey: index) {
                    adj.removeFromSuperview()
                }
                mountCanvas(on: index)
            }
        }

        // MARK: Bitmap fill

        /// Render bitmaps for any visible slots that don't have one yet (and aren't live canvas slots).
        private func fillVisibleBitmaps() {
            guard let scrollView, let containerView else { return }
            let visibleRect = scrollView.convert(scrollView.bounds, to: containerView)
            let liveIndices = Set(liveCanvases.keys)
            for (i, slot) in slots.enumerated() {
                guard !liveIndices.contains(i), slot.bitmap == nil, slot.frame.intersects(visibleRect) else { continue }
                slot.bitmap = PageBitmapRenderer.render(page: sortedPages[i])
            }
        }

        // MARK: Teardown

        /// Remove all slots and live canvases from the view hierarchy.
        private func tearDown() {
            tearDownAdjacentCanvases()
            for (_, canvas) in liveCanvases {
                canvas.flushToModel()
                canvas.removeFromSuperview()
            }
            liveCanvases.removeAll()
            lastReconciledVisible = []
            for slot in slots {
                slot.removeFromSuperview()
            }
            slots.removeAll()
            sortedPages = []
            pageFrames = []
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

        private func restoreViewport(_ viewport: ViewportState, containerSize: CGSize, frames: [CGRect]) {
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

        // MARK: Layout helpers

        func centerContainerIfNeeded() {
            guard let scrollView, let containerView else { return }
            containerView.frame.origin = PageLayout.getCenteringOrigin(
                contentSize: containerView.frame.size, scrollBounds: scrollView.bounds.size
            )
        }

        /// Compute current page index from scroll position.
        private func currentPageIndex() -> Int {
            guard let scrollView, let containerView, !pageFrames.isEmpty else { return 0 }
            let centerY = (scrollView.contentOffset.y + scrollView.bounds.height / 2)
                / max(scrollView.zoomScale, 0.001) - containerView.frame.minY
            let raw = PageLayout.getCurrentPageIndex(centerY: centerY, pageFrames: pageFrames)
            return min(raw, max(0, sortedPages.count - 1))
        }

        private func updateCurrentPage() {
            guard !pages.isEmpty else { return }
            let index = currentPageIndex()
            onCurrentPageChanged?(index)
            // Deliver the centered page's undo manager if it has a live canvas.
            if let canvas = liveCanvases[index] {
                onUndoManagerReady(canvas.undoManagerForPage)
            }
        }

        /// Handle scroll settling — reconcile canvases, fill bitmaps, mount adjacents.
        private func handleScrollSettle() {
            updateCurrentPage()
            // Invalidate cache so reconcile always runs fresh on settle.
            lastReconciledVisible = []
            reconcileLiveCanvases()
            fillVisibleBitmaps()
            mountAdjacentCanvases()
            let zoom = scrollView?.zoomScale ?? 1.0
            liveCanvases.values.forEach { $0.updateZoomScale(zoom) }
            // Clear bitmaps that are off-screen and outside the live + adjacent range.
            let canvasIndices = Set(liveCanvases.keys).union(adjacentCanvases.keys)
            let visible = visiblePageIndices()
            for (i, slot) in slots.enumerated() where slot.bitmap != nil
                && !canvasIndices.contains(i) && !visible.contains(i)
            {
                slot.bitmap = nil
            }
        }

        /// Mount display-only canvases on pages ±1 from the visible range for vector-sharp rendering.
        private func mountAdjacentCanvases() {
            let visible = Set(liveCanvases.keys)
            guard !visible.isEmpty else { return }
            let minVisible = visible.min()!
            let maxVisible = visible.max()!
            // ±1 from the visible range edges, excluding pages that already have live canvases.
            let wanted = Set([minVisible - 1, maxVisible + 1]
                .filter { $0 >= 0 && $0 < sortedPages.count && !visible.contains($0) })

            // Remove canvases that are no longer adjacent.
            for index in adjacentCanvases.keys where !wanted.contains(index) {
                if index < slots.count {
                    slots[index].bitmap = PageBitmapRenderer.render(page: sortedPages[index])
                }
                adjacentCanvases.removeValue(forKey: index)?.removeFromSuperview()
            }

            // Mount new adjacent canvases where needed.
            for i in wanted where adjacentCanvases[i] == nil {
                let page = sortedPages[i]
                let frame = CGRect(origin: .zero, size: pageFrames[i].size)
                let style = ToolStyle.from(toolbar: toolbar)
                let canvas = DrawingCanvasView(page: page, frame: frame, toolStyle: style, onPageMutated: onPageMutated)
                // Display-only — no pencil input, no interaction delegate.
                canvas.isUserInteractionEnabled = false
                slots[i].bitmap = nil
                slots[i].addSubview(canvas)
                // Update zoom AFTER addSubview so the view has a window and correct screen scale.
                canvas.updateZoomScale(scrollView?.zoomScale ?? 1.0)
                adjacentCanvases[i] = canvas
            }
        }

        /// Remove all adjacent display canvases, optionally snapshotting them to bitmaps.
        private func tearDownAdjacentCanvases() {
            for (index, canvas) in adjacentCanvases {
                canvas.removeFromSuperview()
                if index >= 0, index < sortedPages.count, index < slots.count {
                    slots[index].bitmap = PageBitmapRenderer.render(page: sortedPages[index])
                }
            }
            adjacentCanvases.removeAll()
        }

        // MARK: Scroll-to-page

        private func scrollToPage(index: Int) {
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

        private func applyPendingScroll(frames: [CGRect]) {
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

        // MARK: UIScrollViewDelegate

        func viewForZooming(in _: UIScrollView) -> UIView? {
            containerView
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            pullController.update(for: scrollView)
            // Teardown off-screen canvases during scroll to free memory (no mounts — that waits for settle).
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
            // If no deceleration, scroll is settled — swap focus now.
            if !decelerate { handleScrollSettle() }
        }

        func scrollViewDidEndDecelerating(_: UIScrollView) {
            handleScrollSettle()
        }

        // MARK: Canvas interaction

        func pageCanvasViewDidBeginUsingTool(_ view: DrawingCanvasView) -> Bool {
            // Stop any in-flight momentum immediately so Pencil-down behaves like finger-down.
            if let scrollView {
                scrollView.stopScrollingAndZooming()
                // Notify the test seam that a momentum stop was requested.
                onRequestStopScrollMomentum?(scrollView)
                onUndoManagerReady(view.undoManagerForPage)
                // While drawing is active, keep scrolling disabled.
                scrollView.isScrollEnabled = false
                return true
            }
            onUndoManagerReady(view.undoManagerForPage)
            return true
        }

        func pageCanvasViewDidEndUsingTool(_: DrawingCanvasView) {
            scrollView?.isScrollEnabled = true
        }

        // MARK: Pencil

        func pencilInteractionDidTap(_: UIPencilInteraction) {
            onPencilDoubleTap?()
        }
    }
}

extension Notification.Name {
    static let flushDrawings = Notification.Name("SupaNotes.flushDrawings")
}
