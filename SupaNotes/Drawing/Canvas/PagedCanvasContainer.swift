import SwiftUI
import PencilKit

struct PagedCanvasContainer: UIViewRepresentable {
    @Binding var pages: [Page]
    var tool: PKTool
    var onUndoManagerReady: (UndoManager?) -> Void
    var onPencilDoubleTap: (() -> Void)?
    var onCurrentPageChanged: ((Int) -> Void)?
    var addPage: () -> Void
    var addPageAbove: (() -> Void)?

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = UIColor(named: "PaperBackground") ?? UIColor.systemGroupedBackground
        scrollView.showsVerticalScrollIndicator = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = Design.Zoom.min
        scrollView.maximumZoomScale = Design.Zoom.max

        let containerView = UIView()
        containerView.tag = 999
        scrollView.addSubview(containerView)

        let c = context.coordinator
        c.layoutManager.scrollView = scrollView
        c.layoutManager.containerView = containerView

        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = c
        scrollView.addInteraction(pencilInteraction)

        c.rebuildPages(pages: pages, tool: tool, viewport: nil)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        let c = context.coordinator
        c.pages = pages
        c.tool = tool
        c.onPencilDoubleTap = onPencilDoubleTap
        c.onCurrentPageChanged = onCurrentPageChanged
        c.addPage = addPage
        c.addPageAbove = addPageAbove

        c.layoutManager.canvasViews.forEach { $0.tool = tool }

        let containerWidth = c.layoutManager.containerView?.frame.width ?? 0
        let needsRebuild = c.layoutManager.canvasViews.count != pages.count
            || (!c.layoutManager.hasCompletedInitialLayout && scrollView.bounds.width > 0 && abs(containerWidth - scrollView.bounds.width) > 1)

        if needsRebuild {
            c.layoutManager.hasCompletedInitialLayout = scrollView.bounds.width > 0
            let viewport = c.layoutManager.captureViewportState(pages: pages)
            c.rebuildPages(pages: pages, tool: tool, viewport: viewport)
        }
        c.layoutManager.centerContainerIfNeeded()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            pages: pages,
            tool: tool,
            onUndoManagerReady: onUndoManagerReady,
            onPencilDoubleTap: onPencilDoubleTap,
            onCurrentPageChanged: onCurrentPageChanged,
            addPage: addPage,
            addPageAbove: addPageAbove
        )
    }

    // MARK: - Scroll Action
    enum ScrollAfterRebuild: Equatable {
        case none
        case scrollToFirst
        case scrollToLast
    }

    // MARK: - Coordinator
    class Coordinator: NSObject, UIScrollViewDelegate, PKCanvasViewDelegate, UIPencilInteractionDelegate {
        var pages: [Page]
        var tool: PKTool
        var onUndoManagerReady: (UndoManager?) -> Void
        var onPencilDoubleTap: (() -> Void)?
        var onCurrentPageChanged: ((Int) -> Void)?
        var addPage: () -> Void
        var addPageAbove: (() -> Void)?

        let layoutManager = PageLayoutManager()
        let pullController = PullToAddController()
        let saveController = DrawingSaveController()
        var pendingScroll: ScrollAfterRebuild = .none
        var isUsingTool = false
        var pendingPresentationBand: PresentationZoomBand?
        var lastZoomAnchorInScrollView: CGPoint?

        init(
            pages: [Page],
            tool: PKTool,
            onUndoManagerReady: @escaping (UndoManager?) -> Void,
            onPencilDoubleTap: (() -> Void)?,
            onCurrentPageChanged: ((Int) -> Void)?,
            addPage: @escaping () -> Void,
            addPageAbove: (() -> Void)?
        ) {
            self.pages = pages
            self.tool = tool
            self.onUndoManagerReady = onUndoManagerReady
            self.onPencilDoubleTap = onPencilDoubleTap
            self.onCurrentPageChanged = onCurrentPageChanged
            self.addPage = addPage
            self.addPageAbove = addPageAbove
            super.init()
            NotificationCenter.default.addObserver(
                forName: Notification.Name("SupaNotes.scrollToPage"),
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let idx = note.object as? Int else { return }
                self?.layoutManager.scrollToPage(index: idx)
            }
            NotificationCenter.default.addObserver(
                forName: Notification.Name("SupaNotes.flushDrawings"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                for canvas in self.layoutManager.canvasViews {
                    self.saveController.immediateSave(canvasView: canvas, pages: self.pages)
                }
            }
        }

        deinit { NotificationCenter.default.removeObserver(self) }

        func rebuildPages(pages: [Page], tool: PKTool, viewport: PageLayoutManager.ViewportState?) {
            layoutManager.rebuildPages(
                pages: pages,
                tool: tool,
                delegate: self,
                pullController: pullController,
                pendingScroll: &pendingScroll,
                presentationBand: pendingPresentationBand ?? layoutManager.presentationBand,
                viewport: viewport,
                onUndoManagerReady: onUndoManagerReady
            )
            pendingPresentationBand = nil
        }

        private func flushDrawings() {
            for canvas in layoutManager.canvasViews {
                saveController.immediateSave(canvasView: canvas, pages: pages)
            }
        }

        private func applyPresentationBandIfNeeded() {
            let preferredBand = layoutManager.preferredPresentationBand()
            guard preferredBand != layoutManager.presentationBand else { return }
            guard !isUsingTool else {
                pendingPresentationBand = preferredBand
                return
            }

            flushDrawings()
            pendingPresentationBand = preferredBand
            let viewport = layoutManager.captureViewportState(pages: pages, anchorInScrollView: zoomAnchorInScrollView())
            rebuildPages(pages: pages, tool: tool, viewport: viewport)
        }

        private func zoomAnchorInScrollView() -> CGPoint? {
            if let lastZoomAnchorInScrollView {
                return lastZoomAnchorInScrollView
            }
            guard let scrollView = layoutManager.scrollView else { return nil }
            return scrollView.pinchGestureRecognizer?.location(in: scrollView)
        }

        // MARK: - UIScrollViewDelegate
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { layoutManager.containerView }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            layoutManager.updateCurrentPage(pages: pages, onCurrentPageChanged: onCurrentPageChanged)
            pullController.update(for: scrollView)
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            if let pinch = scrollView.pinchGestureRecognizer {
                lastZoomAnchorInScrollView = pinch.location(in: scrollView)
            }
            layoutManager.centerContainerIfNeeded()
            layoutManager.updateCurrentPage(pages: pages, onCurrentPageChanged: onCurrentPageChanged)
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            layoutManager.centerContainerIfNeeded()
            applyPresentationBandIfNeeded()
            lastZoomAnchorInScrollView = nil
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            let scroll = pullController.handleEndDragging(addPage: addPage, addPageAbove: addPageAbove)
            if scroll != .none {
                pendingScroll = scroll
            }
        }

        // MARK: - PKCanvasViewDelegate
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            saveController.debouncedSave(canvasView: canvasView, pages: pages)
        }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            isUsingTool = true
            onUndoManagerReady(canvasView.undoManager)
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            saveController.immediateSave(canvasView: canvasView, pages: pages)
            isUsingTool = false
            if pendingPresentationBand != nil {
                let viewport = layoutManager.captureViewportState(pages: pages, anchorInScrollView: zoomAnchorInScrollView())
                rebuildPages(pages: pages, tool: tool, viewport: viewport)
            }
        }

        // MARK: - UIPencilInteractionDelegate
        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
            onPencilDoubleTap?()
        }
    }
}
