import SwiftUI
import UIKit

/// Main container for all pages in a note — a vertically-scrolling, zoomable UIKit scroll view
/// bridged into SwiftUI. Apple Pencil draws; fingers scroll and zoom.
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

        // Sync toolbar to every canvas.
        let style = ToolStyle.from(toolbar: toolbar)
        c.canvasViews.forEach { $0.updateToolStyle(style) }

        // Rebuild when page count changes or on first real layout.
        let containerWidth = c.containerView?.frame.width ?? 0
        let needsRebuild = c.canvasViews.count != pages.count
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

    /// UIKit bridge: owns scroll/zoom delegation, canvas views, pencil interaction, and pull-to-add.
    final class Coordinator: NSObject, UIScrollViewDelegate, UIPencilInteractionDelegate, DrawingCanvasDelegate {

        // MARK: External state (updated each SwiftUI pass)

        var pages: [Page]
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

        var canvasViews: [DrawingCanvasView] = []
        var hasCompletedInitialLayout = false
        let pullController = PullToAddController()
        var pendingScroll: ScrollAfterRebuild = .none

        /// Cached page sizes from last rebuild (for viewport math).
        private var cachedPageSizes: [CGSize] = []
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
                self?.canvasViews.forEach { $0.flushToModel() }
            }
        }

        deinit { NotificationCenter.default.removeObserver(self) }

        // MARK: Page rebuild

        func rebuildPages(pages: [Page], toolbar: ToolbarState, viewport: ViewportState?) {
            guard let containerView, let scrollView else { return }

            let sorted = pages.sorted { $0.orderIndex < $1.orderIndex }
            let pageSizes = sorted.map(\.size)
            cachedPageSizes = pageSizes

            let cw = PageLayout.getCanvasWidth(pageSizes: pageSizes, gap: pageGap, scrollWidth: scrollView.bounds.width)
            let totalHeight = PageLayout.getContainerHeight(pageSizes: pageSizes, gap: pageGap)
            let totalSize = CGSize(width: cw, height: totalHeight)
            let frames = PageLayout.getPageFramesAsCGRects(pageSizes: pageSizes, gap: pageGap, containerWidth: cw)
            let style = ToolStyle.from(toolbar: toolbar)

            UIView.performWithoutAnimation {
                // Tear down old views.
                canvasViews.forEach { $0.removeFromSuperview() }
                canvasViews.removeAll()
                containerView.bounds.size = totalSize

                // Create new canvas views.
                canvasViews = frames.enumerated().map { i, frame in
                    let canvas = DrawingCanvasView(
                        page: sorted[i], frame: frame, toolStyle: style, onPageMutated: onPageMutated
                    )
                    canvas.tag = i
                    canvas.interactionDelegate = self
                    canvas.layer.shadowColor = UIColor.black.cgColor
                    canvas.layer.shadowOpacity = Float(Design.Shadow.page.opacity)
                    canvas.layer.shadowOffset = CGSize(width: Design.Shadow.page.x, height: Design.Shadow.page.y)
                    canvas.layer.shadowRadius = Design.Shadow.page.radius
                    containerView.addSubview(canvas)
                    return canvas
                }

                canvasViews.forEach { $0.updateZoomScale(scrollView.zoomScale) }

                // Restore viewport or set initial layout.
                if let viewport {
                    restoreViewport(viewport, containerSize: totalSize, frames: frames)
                } else {
                    scrollView.contentSize = PageLayout.getScrollContentSize(containerSize: totalSize, zoomScale: scrollView.zoomScale)
                    centerContainerIfNeeded()
                }

                containerView.layoutIfNeeded()
                scrollView.layoutIfNeeded()
            }

            pullController.setupIndicators(in: scrollView)
            applyPendingScroll(frames: frames)
            centerContainerIfNeeded()

            // Deliver first page's undo manager on next run loop.
            if let first = canvasViews.first {
                DispatchQueue.main.async { [weak self] in self?.onUndoManagerReady(first.undoManagerForPage) }
            }
        }

        // MARK: Viewport

        func captureViewport() -> ViewportState? {
            guard let scrollView, let containerView, !pages.isEmpty else { return nil }
            let frames = currentPageFrames()
            return PageLayout.captureViewport(
                scrollOffset: scrollView.contentOffset,
                scrollBoundsSize: scrollView.bounds.size,
                containerOrigin: containerView.frame.origin,
                zoomScale: scrollView.zoomScale,
                pageFrames: frames
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

        private func currentPageFrames() -> [CGRect] {
            let cw = containerView?.bounds.width ?? 0
            return PageLayout.getPageFramesAsCGRects(pageSizes: cachedPageSizes, gap: pageGap, containerWidth: cw)
        }

        private func visibleCanvasViews() -> [DrawingCanvasView] {
            guard let scrollView, let containerView else { return canvasViews }
            let visibleRect = scrollView.convert(scrollView.bounds, to: containerView)
            return canvasViews.filter { $0.frame.intersects(visibleRect) }
        }

        private func updateCurrentPage() {
            guard let scrollView, let containerView, !pages.isEmpty else { return }
            let centerY = (scrollView.contentOffset.y + scrollView.bounds.height / 2)
                / max(scrollView.zoomScale, 0.001) - containerView.frame.minY
            let index = PageLayout.getCurrentPageIndex(centerY: centerY, pageFrames: currentPageFrames())
            onCurrentPageChanged?(min(index, max(0, pages.count - 1)))
        }

        // MARK: Scroll-to-page

        private func scrollToPage(index: Int) {
            guard let scrollView, let containerView, canvasViews.indices.contains(index) else { return }
            scrollView.zoomScale = 1.0
            scrollView.contentSize = PageLayout.getScrollContentSize(containerSize: containerView.bounds.size, zoomScale: 1.0)
            centerContainerIfNeeded()
            let frames = currentPageFrames()
            guard index < frames.count else { return }
            let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
            let targetY = min(max(0, containerView.frame.minY + frames[index].minY - 20), maxY)
            UIView.animate(withDuration: 0.3) {
                scrollView.contentOffset = CGPoint(x: 0, y: targetY)
            } completion: { [weak self] _ in
                self?.visibleCanvasViews().forEach { $0.updateZoomScale(1.0) }
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

        func viewForZooming(in _: UIScrollView) -> UIView? { containerView }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            updateCurrentPage()
            pullController.update(for: scrollView)
        }

        func scrollViewDidZoom(_: UIScrollView) {
            centerContainerIfNeeded()
            updateCurrentPage()
        }

        func scrollViewDidEndZooming(_: UIScrollView, with _: UIView?, atScale scale: CGFloat) {
            visibleCanvasViews().forEach { $0.updateZoomScale(scale) }
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            let scroll = pullController.handleEndDragging(addPage: addPage, addPageAbove: addPageAbove)
            if scroll != .none { pendingScroll = scroll }
            if !decelerate { visibleCanvasViews().forEach { $0.updateZoomScale(scrollView.zoomScale) } }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            visibleCanvasViews().forEach { $0.updateZoomScale(scrollView.zoomScale) }
        }

        // MARK: Canvas interaction

        func pageCanvasViewDidBeginUsingTool(_ view: DrawingCanvasView) {
            scrollView?.isScrollEnabled = false
            onUndoManagerReady(view.undoManagerForPage)
        }

        func pageCanvasViewDidEndUsingTool(_: DrawingCanvasView) {
            scrollView?.isScrollEnabled = true
        }

        // MARK: Pencil

        func pencilInteractionDidTap(_: UIPencilInteraction) { onPencilDoubleTap?() }
    }
}

extension Notification.Name {
    static let flushDrawings = Notification.Name("SupaNotes.flushDrawings")
}
