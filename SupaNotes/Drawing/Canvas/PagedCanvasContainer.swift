import SwiftUI
import PencilKit

struct PagedCanvasContainer: UIViewRepresentable {
    @Binding var pages: [Page]
    var tool: PKTool
    var onUndoManagerReady: (UndoManager?) -> Void
    var onPencilDoubleTap: (() -> Void)?
    var onWritingStateChanged: ((Bool) -> Void)?
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

        c.rebuildPages(pages: pages, tool: tool)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        let c = context.coordinator
        c.pages = pages
        c.tool = tool
        c.onPencilDoubleTap = onPencilDoubleTap
        c.onWritingStateChanged = onWritingStateChanged
        c.onCurrentPageChanged = onCurrentPageChanged
        c.addPage = addPage
        c.addPageAbove = addPageAbove

        c.layoutManager.canvasViews.forEach { $0.tool = tool }

        let containerWidth = c.layoutManager.containerView?.frame.width ?? 0
        let needsRebuild = c.layoutManager.canvasViews.count != pages.count
            || (!c.layoutManager.hasCompletedInitialLayout && scrollView.bounds.width > 0 && abs(containerWidth - scrollView.bounds.width) > 1)

        if needsRebuild {
            c.layoutManager.hasCompletedInitialLayout = scrollView.bounds.width > 0
            c.rebuildPages(pages: pages, tool: tool)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            pages: pages,
            tool: tool,
            onUndoManagerReady: onUndoManagerReady,
            onPencilDoubleTap: onPencilDoubleTap,
            onWritingStateChanged: onWritingStateChanged,
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
    class Coordinator: NSObject {
        var pages: [Page]
        var tool: PKTool
        var onUndoManagerReady: (UndoManager?) -> Void
        var onPencilDoubleTap: (() -> Void)?
        var onWritingStateChanged: ((Bool) -> Void)?
        var onCurrentPageChanged: ((Int) -> Void)?
        var addPage: () -> Void
        var addPageAbove: (() -> Void)?

        let layoutManager = PageLayoutManager()
        let pullController = PullToAddController()
        let saveController = DrawingSaveController()
        var pendingScroll: ScrollAfterRebuild = .none

        init(
            pages: [Page],
            tool: PKTool,
            onUndoManagerReady: @escaping (UndoManager?) -> Void,
            onPencilDoubleTap: (() -> Void)?,
            onWritingStateChanged: ((Bool) -> Void)?,
            onCurrentPageChanged: ((Int) -> Void)?,
            addPage: @escaping () -> Void,
            addPageAbove: (() -> Void)?
        ) {
            self.pages = pages
            self.tool = tool
            self.onUndoManagerReady = onUndoManagerReady
            self.onPencilDoubleTap = onPencilDoubleTap
            self.onWritingStateChanged = onWritingStateChanged
            self.onCurrentPageChanged = onCurrentPageChanged
            self.addPage = addPage
            self.addPageAbove = addPageAbove
        }

        func rebuildPages(pages: [Page], tool: PKTool) {
            layoutManager.rebuildPages(
                pages: pages,
                tool: tool,
                delegate: self,
                pullController: pullController,
                pendingScroll: &pendingScroll,
                onUndoManagerReady: onUndoManagerReady
            )
        }
    }
}

// MARK: - UIScrollViewDelegate
extension PagedCanvasContainer.Coordinator: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        layoutManager.containerView
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        layoutManager.updateCurrentPage(pages: pages, onCurrentPageChanged: onCurrentPageChanged)
        pullController.update(for: scrollView)
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        layoutManager.centerContainerIfNeeded()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        let scroll = pullController.handleEndDragging(addPage: addPage, addPageAbove: addPageAbove)
        if scroll != .none {
            pendingScroll = scroll
        }
    }
}

// MARK: - PKCanvasViewDelegate
extension PagedCanvasContainer.Coordinator: PKCanvasViewDelegate {
    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        saveController.debouncedSave(canvasView: canvasView, pages: pages)
    }

    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        onWritingStateChanged?(true)
        onUndoManagerReady(canvasView.undoManager)
    }

    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        onWritingStateChanged?(false)
        saveController.immediateSave(canvasView: canvasView, pages: pages)
    }
}

// MARK: - UIPencilInteractionDelegate
extension PagedCanvasContainer.Coordinator: UIPencilInteractionDelegate {
    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        onPencilDoubleTap?()
    }
}
