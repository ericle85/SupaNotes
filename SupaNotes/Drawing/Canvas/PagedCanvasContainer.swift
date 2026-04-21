import MetalKit
import SwiftUI

struct PagedCanvasContainer: UIViewRepresentable {
    @Binding var pages: [Page]
    var tool: DrawingTool
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
        scrollView.delaysContentTouches = false

        if #available(iOS 9.1, *) {
            let fingerTouchType = NSNumber(value: UITouch.TouchType.direct.rawValue)
            scrollView.panGestureRecognizer.allowedTouchTypes = [fingerTouchType]
            scrollView.pinchGestureRecognizer?.allowedTouchTypes = [fingerTouchType]
        }

        let containerView = UIView()
        containerView.tag = 999
        scrollView.addSubview(containerView)

        let coordinator = context.coordinator
        coordinator.layoutManager.scrollView = scrollView
        coordinator.layoutManager.containerView = containerView

        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = coordinator
        scrollView.addInteraction(pencilInteraction)

        coordinator.rebuildPages(pages: pages, tool: tool, viewport: nil)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.pages = pages
        coordinator.tool = tool
        coordinator.onPencilDoubleTap = onPencilDoubleTap
        coordinator.onCurrentPageChanged = onCurrentPageChanged
        coordinator.addPage = addPage
        coordinator.addPageAbove = addPageAbove

        coordinator.layoutManager.canvasViews.forEach { tool.apply(to: $0) }

        let containerWidth = coordinator.layoutManager.containerView?.frame.width ?? 0
        let needsRebuild = coordinator.layoutManager.canvasViews.count != pages.count
            || (!coordinator.layoutManager.hasCompletedInitialLayout
                && scrollView.bounds.width > 0
                && abs(containerWidth - scrollView.bounds.width) > 1)

        if needsRebuild {
            coordinator.layoutManager.hasCompletedInitialLayout = scrollView.bounds.width > 0
            let viewport = coordinator.layoutManager.captureViewportState(pages: pages)
            coordinator.rebuildPages(pages: pages, tool: tool, viewport: viewport)
        }

        coordinator.layoutManager.centerContainerIfNeeded()
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

    enum ScrollAfterRebuild: Equatable {
        case none
        case scrollToFirst
        case scrollToLast
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIPencilInteractionDelegate, ActionObserver {
        var pages: [Page]
        var tool: DrawingTool
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

        init(
            pages: [Page],
            tool: DrawingTool,
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
                guard let index = note.object as? Int else { return }
                self?.layoutManager.scrollToPage(index: index)
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

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func rebuildPages(pages: [Page], tool: DrawingTool, viewport: PageLayoutManager.ViewportState?) {
            layoutManager.rebuildPages(
                pages: pages,
                tool: tool,
                observer: self,
                pullController: pullController,
                pendingScroll: &pendingScroll,
                viewport: viewport,
                onUndoManagerReady: onUndoManagerReady
            )
            if let scrollView = layoutManager.scrollView {
                updateCanvasRenderingScale(for: scrollView)
            }
        }

        func viewForZooming(in _: UIScrollView) -> UIView? {
            layoutManager.containerView
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            layoutManager.updateCurrentPage(pages: pages, onCurrentPageChanged: onCurrentPageChanged)
            pullController.update(for: scrollView)
            updateCanvasRenderingScale(for: scrollView)
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            layoutManager.centerContainerIfNeeded()
            layoutManager.updateCurrentPage(pages: pages, onCurrentPageChanged: onCurrentPageChanged)
            updateCanvasRenderingScale(for: scrollView)
        }

        func scrollViewDidEndDragging(_: UIScrollView, willDecelerate _: Bool) {
            let scroll = pullController.handleEndDragging(addPage: addPage, addPageAbove: addPageAbove)
            if scroll != .none {
                pendingScroll = scroll
            }
        }

        func canvas(_ canvas: Canvas, didBeginLineAt _: CGPoint, force _: CGFloat) {
            isUsingTool = true
            onUndoManagerReady(nil)
            if let view = canvas as? SupaCanvasView {
                saveController.debouncedSave(canvasView: view, pages: pages)
            }
        }

        func canvas(_ canvas: Canvas, didMoveLineTo _: CGPoint, force _: CGFloat) {
            if let view = canvas as? SupaCanvasView {
                saveController.debouncedSave(canvasView: view, pages: pages)
            }
        }

        func canvas(_ canvas: Canvas, didFinishLineAt _: CGPoint, force _: CGFloat) {
            if let view = canvas as? SupaCanvasView {
                saveController.immediateSave(canvasView: view, pages: pages)
            }
            isUsingTool = false
        }

        func pencilInteractionDidTap(_: UIPencilInteraction) {
            onPencilDoubleTap?()
        }

        private func updateCanvasRenderingScale(for scrollView: UIScrollView) {
            guard let containerView = layoutManager.containerView else { return }

            let zoom = max(scrollView.zoomScale, 0.001)
            let visibleInContainer = CGRect(
                x: (scrollView.contentOffset.x - containerView.frame.minX) / zoom,
                y: (scrollView.contentOffset.y - containerView.frame.minY) / zoom,
                width: scrollView.bounds.width / zoom,
                height: scrollView.bounds.height / zoom
            ).insetBy(dx: -PageConstants.pageWidth * 0.5, dy: -PageConstants.pageHeight * 0.5)

            let baseScale = UIScreen.main.scale
            let boostedScale = min(baseScale * zoom, 4.0)

            for canvas in layoutManager.canvasViews {
                let targetScale = canvas.frame.intersects(visibleInContainer) ? boostedScale : baseScale
                if abs(canvas.contentScaleFactor - targetScale) < 0.1 { continue }

                canvas.contentScaleFactor = targetScale
                canvas.drawableSize = CGSize(
                    width: canvas.bounds.width * targetScale,
                    height: canvas.bounds.height * targetScale
                )
                canvas.invalidateElementRenderBuffers()
                canvas.redraw()
            }
        }
    }
}
