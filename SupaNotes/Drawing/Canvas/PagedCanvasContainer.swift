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
    var captureToken: AgentCaptureToken?

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

        // Register page capture on the token
        c.scrollViewRef = scrollView
        captureToken?.captureCurrentPage = { [weak c] (screenRect: CGRect?) in
            c?.captureCurrentPageImage(highlightScreenRect: screenRect)
        }
        captureToken?.imageRectToScreenRect = { [weak c] (imageRect: CGRect) in
            c?.imageRectToScreenRect(imageRect) ?? .zero
        }
        captureToken?.tapAtImagePoint = { [weak c] (imagePoint: CGPoint) in
            // Caller converts normalized point → image space before calling this.
            // Build a fixed-size crop box and return screen rect via imageRectToScreenRect.
            let boxW: CGFloat = 120
            let boxH: CGFloat = 40
            let imageRect = CGRect(
                x: imagePoint.x - boxW / 2,
                y: imagePoint.y - boxH / 2,
                width: boxW,
                height: boxH
            )
            let _ = c?.imageRectToScreenRect(imageRect)
        }

        DispatchQueue.main.async {
            scrollView.zoomScale = 1.0 / PageConstants.renderScale
        }

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
    class Coordinator: NSObject, UIScrollViewDelegate, PKCanvasViewDelegate, UIPencilInteractionDelegate {
        var pages: [Page]
        var tool: PKTool
        var onUndoManagerReady: (UndoManager?) -> Void
        var onPencilDoubleTap: (() -> Void)?
        var onWritingStateChanged: ((Bool) -> Void)?
        var onCurrentPageChanged: ((Int) -> Void)?
        var addPage: () -> Void
        var addPageAbove: (() -> Void)?
        var currentVisiblePageIndex: Int = 0
        weak var scrollViewRef: UIScrollView?

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

        // MARK: - UIScrollViewDelegate
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { layoutManager.containerView }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            layoutManager.updateCurrentPage(pages: pages, onCurrentPageChanged: { [weak self] idx in
                self?.currentVisiblePageIndex = idx
                self?.onCurrentPageChanged?(idx)
            } )
            pullController.update(for: scrollView)
        }

        func captureCurrentPageImage(highlightScreenRect: CGRect? = nil) -> UIImage? {
            let canvasViews = layoutManager.canvasViews
            guard currentVisiblePageIndex < canvasViews.count else { return nil }
            let canvasView = canvasViews[currentVisiblePageIndex]
            let pageSize = CGSize(width: PageConstants.pageWidth, height: PageConstants.pageHeight)
            let canvasScale = 1.0 / PageConstants.renderScale

            let renderer = UIGraphicsImageRenderer(size: pageSize)
            return renderer.image { ctx in
                UIColor.white.setFill()
                UIRectFill(CGRect(origin: .zero, size: pageSize))
                // Draw canvas scaled down to page size
                ctx.cgContext.scaleBy(x: canvasScale, y: canvasScale)
                canvasView.drawHierarchy(in: canvasView.bounds, afterScreenUpdates: true)
                ctx.cgContext.scaleBy(x: 1.0 / canvasScale, y: 1.0 / canvasScale)
                // Draw selected region annotation
                if let screenRect = highlightScreenRect, let sv = scrollViewRef {
                    let imageRect = screenRectToImageRect(screenRect, scrollView: sv)
                    ctx.cgContext.setFillColor(UIColor.systemBlue.withAlphaComponent(0.15).cgColor)
                    ctx.cgContext.setStrokeColor(UIColor.systemBlue.cgColor)
                    ctx.cgContext.setLineWidth(2)
                    ctx.cgContext.fill(imageRect)
                    ctx.cgContext.stroke(imageRect)
                }
            }
        }

        private func screenRectToImageRect(_ screenRect: CGRect, scrollView: UIScrollView) -> CGRect {
            guard let containerView = layoutManager.containerView else { return .zero }
            let canvasViews = layoutManager.canvasViews
            guard currentVisiblePageIndex < canvasViews.count else { return .zero }
            let pageOriginInContainer = canvasViews[currentVisiblePageIndex].frame.origin
            // Convert screen coords → container coords, subtract current page origin
            func toCanvas(_ p: CGPoint) -> CGPoint { containerView.convert(p, from: nil) }
            let o = toCanvas(screenRect.origin)
            let c = toCanvas(CGPoint(x: screenRect.maxX, y: screenRect.maxY))
            let s = 1.0 / PageConstants.renderScale
            return CGRect(
                x: (o.x - pageOriginInContainer.x) * s,
                y: (o.y - pageOriginInContainer.y) * s,
                width: (c.x - o.x) * s,
                height: (c.y - o.y) * s
            )
        }

        func imageRectToScreenRect(_ imageRect: CGRect) -> CGRect {
            guard let containerView = layoutManager.containerView else { return .zero }
            let canvasViews = layoutManager.canvasViews
            guard currentVisiblePageIndex < canvasViews.count else { return .zero }
            let pageOrigin = canvasViews[currentVisiblePageIndex].frame.origin
            func toScreen(_ p: CGPoint) -> CGPoint {
                let cx = p.x * PageConstants.renderScale + pageOrigin.x
                let cy = p.y * PageConstants.renderScale + pageOrigin.y
                return containerView.convert(CGPoint(x: cx, y: cy), to: nil)
            }
            let o = toScreen(imageRect.origin)
            let c = toScreen(CGPoint(x: imageRect.maxX, y: imageRect.maxY))
            return CGRect(x: o.x, y: o.y, width: c.x - o.x, height: c.y - o.y)
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) { layoutManager.centerContainerIfNeeded() }

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
            onWritingStateChanged?(true)
            onUndoManagerReady(canvasView.undoManager)
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            onWritingStateChanged?(false)
            saveController.immediateSave(canvasView: canvasView, pages: pages)
        }

        // MARK: - UIPencilInteractionDelegate
        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
            onPencilDoubleTap?()
        }
    }
}
