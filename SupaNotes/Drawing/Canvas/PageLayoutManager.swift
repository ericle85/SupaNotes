import UIKit
import PencilKit

class PageLayoutManager {
    weak var scrollView: UIScrollView?
    weak var containerView: UIView?
    var canvasViews: [PKCanvasView] = []
    var hasCompletedInitialLayout = false

    func rebuildPages(
        pages: [Page],
        tool: PKTool,
        delegate: PKCanvasViewDelegate,
        pullController: PullToAddController,
        pendingScroll: inout PagedCanvasContainer.ScrollAfterRebuild,
        onUndoManagerReady: @escaping (UndoManager?) -> Void
    ) {
        guard let containerView = containerView, let scrollView = scrollView else { return }

        if pendingScroll != .none {
            scrollView.zoomScale = 1.0 / PageConstants.renderScale
        }

        canvasViews.forEach { $0.removeFromSuperview() }
        canvasViews.removeAll()

        let sortedPages = pages.sorted { $0.orderIndex < $1.orderIndex }
        let pageW = PageConstants.internalWidth
        let pageH = PageConstants.internalHeight
        let gap = PageConstants.internalGap
        let size = PageLayout.containerSize(pageCount: sortedPages.count, pageW: pageW, pageH: pageH, gap: gap, scrollWidth: scrollView.bounds.width)

        // Set bounds.size (not frame) so we don't clobber a live zoom transform.
        containerView.bounds.size = size
        scrollView.contentSize = PageLayout.scrollContentSize(containerSize: size, zoomScale: scrollView.zoomScale)

        canvasViews = PageLayout.pageFrames(count: sortedPages.count, pageW: pageW, pageH: pageH, gap: gap, containerWidth: size.width)
            .enumerated()
            .map { index, frame in
                let canvas = Self.makeCanvasView(page: sortedPages[index], index: index, frame: frame, tool: tool, delegate: delegate)
                containerView.addSubview(canvas)
                return canvas
            }

        centerContainerIfNeeded()
        pullController.setupIndicators(in: scrollView)
        applyPendingScroll(&pendingScroll, pageH: pageH, gap: gap, pageCount: sortedPages.count)

        if let firstCanvas = canvasViews.first {
            DispatchQueue.main.async {
                onUndoManagerReady(firstCanvas.undoManager)
            }
        }
    }

    private static func makeCanvasView(page: Page, index: Int, frame: CGRect, tool: PKTool, delegate: PKCanvasViewDelegate) -> PKCanvasView {
        let canvasView = SupaCanvasView()
        canvasView.drawingPolicy = .pencilOnly
        canvasView.backgroundColor = page.template.backgroundColor
        canvasView.overrideUserInterfaceStyle = page.template.interfaceStyle
        canvasView.isScrollEnabled = false
        canvasView.tool = tool
        canvasView.tag = index
        canvasView.delegate = delegate

        if let data = page.backgroundImageData, let image = UIImage(data: data) {
            let bg = UIImageView(image: image)
            bg.contentMode = .scaleToFill
            bg.frame = canvasView.bounds
            bg.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            canvasView.insertSubview(bg, at: 0)
            canvasView.isOpaque = false
            canvasView.backgroundColor = .clear
        }

        if !page.drawingData.isEmpty, let drawing = try? PKDrawing(data: page.drawingData) {
            canvasView.drawing = drawing
        }

        canvasView.layer.shadowColor = UIColor.black.cgColor
        canvasView.layer.shadowOpacity = Float(Design.Shadow.page.color)
        canvasView.layer.shadowOffset = CGSize(width: Design.Shadow.page.x, height: Design.Shadow.page.y)
        canvasView.layer.shadowRadius = Design.Shadow.page.radius
        canvasView.frame = frame
        return canvasView
    }

    private func applyPendingScroll(_ pendingScroll: inout PagedCanvasContainer.ScrollAfterRebuild, pageH: CGFloat, gap: CGFloat, pageCount: Int) {
        guard let scrollView = scrollView else { return }
        let action = pendingScroll
        pendingScroll = .none

        let target: CGPoint
        switch action {
        case .none: return
        case .scrollToFirst:
            target = .zero
        case .scrollToLast:
            let lastPageY = gap + CGFloat(pageCount - 1) * (pageH + gap)
            let targetY = max(0, lastPageY - 20)
            let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
            target = CGPoint(x: 0, y: min(targetY, maxY))
        }

        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) {
            scrollView.contentOffset = target
        }
    }

    func centerContainerIfNeeded() {
        guard let scrollView = scrollView, let containerView = containerView else { return }
        containerView.frame.origin = PageLayout.centeringOrigin(
            contentSize: containerView.frame.size,
            scrollBounds: scrollView.bounds.size
        )
    }

    func scrollToPage(index: Int) {
        guard let scrollView = scrollView, canvasViews.indices.contains(index) else { return }
        let pageH = PageConstants.internalHeight
        let gap = PageConstants.internalGap
        let y = gap + CGFloat(index) * (pageH + gap)
        let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        let targetY = min(max(0, y * scrollView.zoomScale - 20), maxY)
        UIView.animate(withDuration: 0.3) {
            scrollView.contentOffset = CGPoint(x: 0, y: targetY)
        }
    }

    func updateCurrentPage(pages: [Page], onCurrentPageChanged: ((Int) -> Void)?) {
        guard let scrollView = scrollView else { return }
        let centerY = (scrollView.contentOffset.y + scrollView.bounds.height / 2) / scrollView.zoomScale
        let pageH = PageConstants.internalHeight
        let gap = PageConstants.internalGap
        let pageIndex = max(0, Int((centerY - gap) / (pageH + gap)))
        onCurrentPageChanged?(min(pageIndex, max(0, pages.count - 1)))
    }
}
