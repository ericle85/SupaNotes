import SwiftUI
import UIKit

/// This is the main container for all pages in a note.
/// Think of it like a physical notebook — all pages are stacked vertically and you
/// scroll up/down to move between them. You can also pinch to zoom in or out on the whole notebook.
///
/// We use Apple's native UIKit scrolling here instead of SwiftUI because UIKit gives
/// much smoother zoom and scroll on iPad, which matters a lot for a drawing app.
struct MultipageCanvasContainer: UIViewRepresentable {
    /// The list of pages in this note, in order. Each one will become a drawing surface on screen.
    @Binding var pages: [Page]

    /// The current toolbar settings — which tool is selected, what color, how thick the line is, etc.
    /// All pages share the same toolbar so switching tools affects every page.
    var toolbar: ToolbarState

    /// Called when the drawing surfaces are ready so the undo/redo buttons
    /// can be wired up to the correct page.
    var onUndoManagerReady: (UndoManager?) -> Void

    /// Called when the user double-taps the barrel of the Apple Pencil.
    /// We use this to switch back to whatever tool they were using before (e.g. pen → eraser → pen).
    var onPencilDoubleTap: (() -> Void)?

    /// Called whenever the user scrolls to a different page.
    /// The parent uses this to update the "Page 2 of 5" counter shown at the bottom.
    var onCurrentPageChanged: ((Int) -> Void)?

    /// Called when the user pulls down past the bottom of the last page and releases.
    /// Adds a new blank page at the end of the note.
    var addPage: () -> Void

    /// Called when the user pulls up past the top of the first page and releases.
    /// Adds a new blank page before the first page.
    var addPageAbove: (() -> Void)?

    /// Called whenever the user draws or erases a stroke on any page.
    /// The parent uses this to mark the note as recently modified.
    var onPageMutated: () -> Void

    /// Sets up the scrollable area and all drawing surfaces the very first time this appears on screen.
    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = UIColor(named: "PaperBackground") ?? UIColor.systemGroupedBackground
        scrollView.showsVerticalScrollIndicator = true
        scrollView.showsHorizontalScrollIndicator = false
        // Bouncing at the top and bottom makes the pull-to-add-page gesture feel natural,
        // like pulling a rubber band.
        scrollView.alwaysBounceVertical = true
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = Design.Zoom.min
        scrollView.maximumZoomScale = Design.Zoom.max
        // Only fingers can scroll or zoom — the Apple Pencil is reserved exclusively for drawing.
        // Without this, a drawing stroke could accidentally scroll the page.
        scrollView.panGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        scrollView.pinchGestureRecognizer?.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]

        // This invisible wrapper holds all the page drawing surfaces.
        // When the user pinches to zoom, this whole wrapper scales up or down together.
        // Tag 999 lets other parts of the code find this wrapper by number if needed.
        let containerView = UIView()
        containerView.tag = 999
        scrollView.addSubview(containerView)

        let coordinator = context.coordinator
        coordinator.layoutManager.scrollView = scrollView
        coordinator.layoutManager.containerView = containerView

        // Register to hear Apple Pencil double-tap events (barrel button press).
        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = coordinator
        scrollView.addInteraction(pencilInteraction)

        // Create and position all the drawing surfaces for the first time.
        coordinator.rebuildPages(pages: pages, toolbar: toolbar, viewport: nil, onPageMutated: onPageMutated)
        return scrollView
    }

    /// Called automatically whenever something the view depends on changes —
    /// for example, when a new page is added, or the user picks a new pen color.
    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        let coordinator = context.coordinator
        // Make sure the coordinator has the latest versions of all the callbacks and data.
        coordinator.pages = pages
        coordinator.toolbar = toolbar
        coordinator.onPencilDoubleTap = onPencilDoubleTap
        coordinator.onCurrentPageChanged = onCurrentPageChanged
        coordinator.addPage = addPage
        coordinator.addPageAbove = addPageAbove
        coordinator.onPageMutated = onPageMutated

        // Tell every drawing surface about the latest tool settings so they all stay in sync.
        let currentStyle = ExcalidrawToolStyle.from(toolbar: toolbar)
        coordinator.layoutManager.canvasViews.forEach { $0.updateToolStyle(currentStyle) }

        // Check whether we need to tear everything down and rebuild from scratch.
        // This is needed when a page is added or deleted, or on the very first appearance
        // when the screen finally tells us how wide it is.
        let containerWidth = coordinator.layoutManager.containerView?.frame.width ?? 0
        let needsRebuild = coordinator.layoutManager.canvasViews.count != pages.count
            || (!coordinator.layoutManager.hasCompletedInitialLayout
                && scrollView.bounds.width > 0
                && abs(containerWidth - scrollView.bounds.width) > 1)

        if needsRebuild {
            coordinator.layoutManager.hasCompletedInitialLayout = scrollView.bounds.width > 0
            // Remember where the user was scrolled to and how far they were zoomed in,
            // so we can put them back in the same spot after rebuilding.
            let viewport = coordinator.layoutManager.captureViewportState(pages: pages)
            coordinator.rebuildPages(pages: pages, toolbar: toolbar, viewport: viewport, onPageMutated: onPageMutated)
        }

        // If the pages are narrower than the screen, keep them centered left-to-right.
        coordinator.layoutManager.centerContainerIfNeeded()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            pages: pages,
            toolbar: toolbar,
            onUndoManagerReady: onUndoManagerReady,
            onPencilDoubleTap: onPencilDoubleTap,
            onCurrentPageChanged: onCurrentPageChanged,
            addPage: addPage,
            addPageAbove: addPageAbove,
            onPageMutated: onPageMutated
        )
    }

    /// After rebuilding the page list, this tells the app which page to jump to.
    enum ScrollAfterRebuild: Equatable {
        case none
        /// Jump to the first page — used when a page is added above the current first page.
        case scrollToFirst
        /// Jump to the last page — used when a new page is added at the bottom.
        case scrollToLast
    }

    /// The coordinator is the middleman between the scrollable area (UIKit) and the rest of the app (SwiftUI).
    /// It listens for scroll, zoom, and pencil events from UIKit and passes the important ones back to SwiftUI.
    final class Coordinator: NSObject, UIScrollViewDelegate, UIPencilInteractionDelegate, ExcalidrawPageCanvasInteractionDelegate {
        var pages: [Page]
        var toolbar: ToolbarState
        var onUndoManagerReady: (UndoManager?) -> Void
        var onPencilDoubleTap: (() -> Void)?
        var onCurrentPageChanged: ((Int) -> Void)?
        var addPage: () -> Void
        var addPageAbove: (() -> Void)?
        var onPageMutated: () -> Void

        /// Responsible for measuring and placing each page drawing surface in the right position on screen.
        let layoutManager = PageLayoutManager()
        /// Watches how far the user has pulled past the top or bottom edge to trigger adding a new page.
        let pullController = PullToAddController()
        /// After the pages are rebuilt, jump to first or last page if needed.
        var pendingScroll: ScrollAfterRebuild = .none

        init(
            pages: [Page],
            toolbar: ToolbarState,
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

            // When the user taps a bookmark, the bookmark list sends a message here
            // telling us which page number to scroll to.
            NotificationCenter.default.addObserver(
                forName: .scrollToPage,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let index = note.object as? Int else { return }
                self?.layoutManager.scrollToPage(index: index)
            }

            // Before exporting or printing, the app sends a message here asking us to
            // make sure all drawn strokes are saved. Without this, the last few strokes
            // might not appear in the exported PDF.
            NotificationCenter.default.addObserver(
                forName: .flushDrawings,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.flushDrawings()
            }
        }

        deinit {
            // Unregister all message listeners when this object is destroyed
            // to avoid receiving messages after it no longer exists.
            NotificationCenter.default.removeObserver(self)
        }

        /// Destroys all the current drawing surfaces and recreates them from scratch.
        /// This is needed when the page list changes (e.g. a page is added or deleted).
        /// The viewport parameter lets us restore the user's scroll position and zoom level afterwards.
        func rebuildPages(
            pages: [Page],
            toolbar: ToolbarState,
            viewport: PageLayoutManager.ViewportState?,
            onPageMutated: @escaping () -> Void
        ) {
            layoutManager.rebuildPages(
                pages: pages,
                toolStyle: ExcalidrawToolStyle.from(toolbar: toolbar),
                interactionDelegate: self,
                pullController: pullController,
                pendingScroll: &pendingScroll,
                viewport: viewport,
                onUndoManagerReady: onUndoManagerReady,
                onPageMutated: onPageMutated
            )
        }

        /// Makes sure all drawing surfaces have saved their latest strokes to the note model.
        /// Called right before exporting or printing so nothing is left out.
        private func flushDrawings() {
            layoutManager.canvasViews.forEach { $0.flushToModel() }
        }

        // MARK: - Scroll and zoom events

        /// When the user pinches to zoom, this tells the system to zoom the page container
        /// (and everything inside it) rather than the scroll view itself.
        func viewForZooming(in _: UIScrollView) -> UIView? {
            layoutManager.containerView
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            // As the user scrolls, figure out which page is in the center of the screen
            // and update the page counter badge at the bottom.
            layoutManager.updateCurrentPage(pages: pages, onCurrentPageChanged: onCurrentPageChanged)
            // Also let the pull-to-add indicator react to how far the user has pulled.
            pullController.update(for: scrollView)
        }

        func scrollViewDidZoom(_: UIScrollView) {
            // After zooming, make sure the pages are still centered left-to-right on screen.
            layoutManager.centerContainerIfNeeded()
            layoutManager.updateCurrentPage(pages: pages, onCurrentPageChanged: onCurrentPageChanged)
        }

        func scrollViewDidEndZooming(_: UIScrollView, with _: UIView?, atScale scale: CGFloat) {
            // Once pinch zoom finishes, redraw only visible pages at the final zoom scale.
            // Off-screen pages keep their cached bitmap until scrolled into view.
            layoutManager.visibleCanvasViews().forEach { $0.updateZoomScale(scale) }
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            // The user just lifted their finger. Check if they pulled far enough
            // to trigger adding a new page at the top or bottom.
            let scroll = pullController.handleEndDragging(addPage: addPage, addPageAbove: addPageAbove)
            if scroll != .none {
                pendingScroll = scroll
            }
            // If scroll stopped immediately (no momentum), update newly-visible pages.
            if !decelerate {
                updateVisiblePagesRenderScale(scrollView)
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            // Momentum scroll finished — update any newly-visible pages' render scale.
            updateVisiblePagesRenderScale(scrollView)
        }

        /// Update render scale on pages that scrolled into view since the last zoom.
        private func updateVisiblePagesRenderScale(_ scrollView: UIScrollView) {
            let scale = scrollView.zoomScale
            layoutManager.visibleCanvasViews().forEach { $0.updateZoomScale(scale) }
        }

        // MARK: - Drawing surface events

        func pageCanvasViewDidBeginUsingTool(_ view: ExcalidrawPageCanvasView) {
            // The user started drawing on a page. Disable scrolling so the drawing stroke
            // doesn't accidentally move the page instead of leaving ink.
            layoutManager.scrollView?.isScrollEnabled = false
            // Point the undo/redo buttons at the page currently being drawn on.
            onUndoManagerReady(view.undoManagerForPage)
        }

        func pageCanvasViewDidEndUsingTool(_: ExcalidrawPageCanvasView) {
            // The user lifted the Pencil. Re-enable scrolling so they can navigate again.
            layoutManager.scrollView?.isScrollEnabled = true
        }

        // MARK: - Apple Pencil events

        func pencilInteractionDidTap(_: UIPencilInteraction) {
            // The user double-tapped the barrel button on the Apple Pencil.
            // Switch back to the tool they were using before (e.g. if they switched to eraser, go back to pen).
            onPencilDoubleTap?()
        }
    }
}

extension Notification.Name {
    static let flushDrawings = Notification.Name("SupaNotes.flushDrawings")
}
