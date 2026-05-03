import SwiftData
import SwiftUI
import UIKit

// Problem: UIKit doesn't give the scroll view a real width until after makeUIView returns.
//          We can't build pages without knowing the width.
// Solution: Override layoutSubviews to detect the first frame where width > 0,
//           run the setup work, then clear it so it never runs again.
final class CanvasScrollView: UIScrollView {
    var buildPagesOnceWidthIsKnown: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let work = buildPagesOnceWidthIsKnown, bounds.width > 0 else { return }
        buildPagesOnceWidthIsKnown = nil
        work()
    }
}

// MARK: - MultipageCanvasContainer

// Vertically-scrolling, zoomable UIKit scroll view bridged into SwiftUI.
// Apple Pencil draws; fingers scroll and zoom.
struct MultipageCanvasContainer: UIViewRepresentable {
    @Binding var pages: [Page]
    var toolbar: ToolbarState
    var onUndoManagerReady: (UndoManager?) -> Void
    var onPencilDoubleTap: (() -> Void)?
    var onCurrentPageChanged: ((Int) -> Void)?
    var addPage: () -> Void
    var addPageAbove: (() -> Void)?
    var onPageMutated: () -> Void

    func makeUIView(context: Context) -> CanvasScrollView {
        let scrollView = CanvasScrollView()
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

        // Hidden until first valid bounds — the callback rebuilds and reveals in the same frame.
        scrollView.alpha = 0
        scrollView.buildPagesOnceWidthIsKnown = { [weak coordinator] in
            guard let c = coordinator else { return }
            c.performInitialLayout()
        }
        return scrollView
    }

    func updateUIView(_: CanvasScrollView, context: Context) {
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

        // Rebuild when pages change (count, identity). Initial layout is handled
        // by CanvasScrollView.buildPagesOnceWidthIsKnown so we skip that path here.
        let pageIDs = pages.map(\.persistentModelID)
        let needsRebuild = c.hasCompletedInitialLayout && pageIDs != c.cachedPageIDs

        if needsRebuild {
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

    // After rebuilding, optionally scroll to first or last page.
    enum ScrollAfterRebuild: Equatable { case none, scrollToFirst, scrollToLast }

    // MARK: - Coordinator
    //
    // Manages a 3-tier rendering system for note pages:
    //
    //   Tier 1 — LIVE canvases:     interactive, accept Apple Pencil input (visible pages)
    //   Tier 2 — ADJACENT canvases: display-only, vector-sharp rendering (±1 from visible)
    //   Tier 3 — BITMAPS:           lightweight raster snapshots (everything else)
    //
    // Split across files:
    //   Coordinator+CanvasLifecycle.swift  — mount/unmount, reconciliation, teardown
    //   Coordinator+ScrollHandling.swift   — scroll delegates, viewport, scroll-to-page
    //   Coordinator+PencilInteraction.swift — drawing + pencil delegates

    final class Coordinator: NSObject, UIScrollViewDelegate, UIPencilInteractionDelegate, DrawingCanvasDelegate {

        // MARK: External State (updated each SwiftUI pass)

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

        // MARK: UIKit References

        weak var scrollView: UIScrollView?
        weak var containerView: UIView?

        // MARK: Canvas State

        // Tier 1: interactive canvases keyed by page index
        var liveCanvases: [Int: DrawingCanvasView] = [:]
        // Tier 2: display-only canvases keyed by page index
        var adjacentCanvases: [Int: DrawingCanvasView] = [:]
        // All page slot views (each slot holds either a canvas or a bitmap)
        var slots: [PageSlotView] = []
        // Sorted pages and their frames from the last rebuild
        var sortedPages: [Page] = []
        var pageFrames: [CGRect] = []

        // Tracks which pages had live canvases on the last reconciliation pass.
        // Reset to [] to force a full re-check on the next reconcile call.
        var lastReconciledVisible: Set<Int> = []

        var cachedPageIDs: [PersistentIdentifier] = []
        var hasCompletedInitialLayout = false
        let pullController = PullToAddController()
        var pendingScroll: ScrollAfterRebuild = .none
        var onRequestStopScrollMomentum: ((UIScrollView) -> Void)?

        let pageGap = PageConstants.pageGap

        // MARK: Init

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

        // MARK: Page Rebuild

        // Called by CanvasScrollView on the first frame with valid bounds.
        // Rebuilds pages and reveals the scroll view in the same layout pass.
        func performInitialLayout() {
            guard let scrollView, !hasCompletedInitialLayout else { return }
            hasCompletedInitialLayout = true
            rebuildPages(pages: pages, toolbar: toolbar, viewport: nil)
            scrollView.alpha = 1
        }

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
                // Tear down all existing canvases and slots.
                tearDown()
                containerView.bounds.size = totalSize
                sortedPages = sorted
                pageFrames = frames

                // Create a lightweight slot for every page.
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

                // Populate all 3 tiers for the current scroll position.
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
    }
}

extension Notification.Name {
    static let flushDrawings = Notification.Name("SupaNotes.flushDrawings")
}
