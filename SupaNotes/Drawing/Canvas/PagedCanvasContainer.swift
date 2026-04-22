import SwiftUI
import UIKit

/// UIKit-backed multipage canvas so we get smooth zoom + scrolling.
struct PagedCanvasContainer: UIViewRepresentable {
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
        // Keep Apple Pencil strokes dedicated to drawing so they never pan the canvas.
        scrollView.panGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        scrollView.pinchGestureRecognizer?.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]

        let containerView = UIView()
        containerView.tag = 999
        scrollView.addSubview(containerView)

        let coordinator = context.coordinator
        coordinator.layoutManager.scrollView = scrollView
        coordinator.layoutManager.containerView = containerView

        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = coordinator
        scrollView.addInteraction(pencilInteraction)

        coordinator.rebuildPages(pages: pages, toolbar: toolbar, viewport: nil, onPageMutated: onPageMutated)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.pages = pages
        coordinator.toolbar = toolbar
        coordinator.onPencilDoubleTap = onPencilDoubleTap
        coordinator.onCurrentPageChanged = onCurrentPageChanged
        coordinator.addPage = addPage
        coordinator.addPageAbove = addPageAbove
        coordinator.onPageMutated = onPageMutated

        let currentStyle = ExcalidrawToolStyle.from(toolbar: toolbar)
        coordinator.layoutManager.canvasViews.forEach { $0.updateToolStyle(currentStyle) }

        let containerWidth = coordinator.layoutManager.containerView?.frame.width ?? 0
        let needsRebuild = coordinator.layoutManager.canvasViews.count != pages.count
            || (!coordinator.layoutManager.hasCompletedInitialLayout
                && scrollView.bounds.width > 0
                && abs(containerWidth - scrollView.bounds.width) > 1)

        if needsRebuild {
            coordinator.layoutManager.hasCompletedInitialLayout = scrollView.bounds.width > 0
            let viewport = coordinator.layoutManager.captureViewportState(pages: pages)
            coordinator.rebuildPages(pages: pages, toolbar: toolbar, viewport: viewport, onPageMutated: onPageMutated)
        }

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

    enum ScrollAfterRebuild: Equatable {
        case none
        case scrollToFirst
        case scrollToLast
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIPencilInteractionDelegate,
        ExcalidrawPageCanvasInteractionDelegate {
        var pages: [Page]
        var toolbar: ToolbarState
        var onUndoManagerReady: (UndoManager?) -> Void
        var onPencilDoubleTap: (() -> Void)?
        var onCurrentPageChanged: ((Int) -> Void)?
        var addPage: () -> Void
        var addPageAbove: (() -> Void)?
        var onPageMutated: () -> Void

        let layoutManager = PageLayoutManager()
        let pullController = PullToAddController()
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

            NotificationCenter.default.addObserver(
                forName: .scrollToPage,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let index = note.object as? Int else { return }
                self?.layoutManager.scrollToPage(index: index)
            }

            NotificationCenter.default.addObserver(
                forName: .flushDrawings,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.flushDrawings()
            }
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

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

        private func flushDrawings() {
            layoutManager.canvasViews.forEach { $0.flushToModel() }
        }

        func viewForZooming(in _: UIScrollView) -> UIView? {
            layoutManager.containerView
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            layoutManager.updateCurrentPage(pages: pages, onCurrentPageChanged: onCurrentPageChanged)
            pullController.update(for: scrollView)
        }

        func scrollViewDidZoom(_: UIScrollView) {
            layoutManager.centerContainerIfNeeded()
            layoutManager.updateCurrentPage(pages: pages, onCurrentPageChanged: onCurrentPageChanged)
        }

        func scrollViewDidEndDragging(_: UIScrollView, willDecelerate _: Bool) {
            let scroll = pullController.handleEndDragging(addPage: addPage, addPageAbove: addPageAbove)
            if scroll != .none {
                pendingScroll = scroll
            }
        }

        func pageCanvasViewDidBeginUsingTool(_ view: ExcalidrawPageCanvasView) {
            // Pause scroll while Pencil is drawing inside a page.
            // This prevents stroke gestures from being stolen by scrolling.
            layoutManager.scrollView?.isScrollEnabled = false
            onUndoManagerReady(view.undoManagerForPage)
        }

        func pageCanvasViewDidEndUsingTool(_: ExcalidrawPageCanvasView) {
            // As soon as drawing ends, let the user scroll again.
            layoutManager.scrollView?.isScrollEnabled = true
        }

        func pencilInteractionDidTap(_: UIPencilInteraction) {
            onPencilDoubleTap?()
        }
    }
}

extension Notification.Name {
    static let flushDrawings = Notification.Name("SupaNotes.flushDrawings")
}
