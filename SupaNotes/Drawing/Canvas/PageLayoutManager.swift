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
            scrollView.zoomScale = 1.0
        }

        canvasViews.forEach { $0.removeFromSuperview() }
        canvasViews.removeAll()

        let sortedPages = pages.sorted { $0.orderIndex < $1.orderIndex }
        let pageW = PageConstants.pageWidth
        let pageH = PageConstants.pageHeight
        let gap = PageConstants.pageGap
        let totalHeight = CGFloat(sortedPages.count) * pageH + CGFloat(max(0, sortedPages.count - 1)) * gap + gap * 2

        containerView.frame = CGRect(
            x: 0, y: 0,
            width: max(pageW + gap * 2, scrollView.bounds.width),
            height: totalHeight
        )
        scrollView.contentSize = containerView.frame.size

        for (index, page) in sortedPages.enumerated() {
            let canvasView = makeCanvasView(for: page, at: index, tool: tool, pageW: pageW, pageH: pageH, gap: gap, containerWidth: containerView.frame.width, delegate: delegate)
            containerView.addSubview(canvasView)
            canvasViews.append(canvasView)
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

    private func makeCanvasView(for page: Page, at index: Int, tool: PKTool, pageW: CGFloat, pageH: CGFloat, gap: CGFloat, containerWidth: CGFloat, delegate: PKCanvasViewDelegate) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.drawingPolicy = .pencilOnly
        canvasView.backgroundColor = .white
        canvasView.overrideUserInterfaceStyle = .light
        canvasView.isScrollEnabled = false
        canvasView.tool = tool
        canvasView.tag = index
        canvasView.delegate = delegate

        if !page.drawingData.isEmpty, let drawing = try? PKDrawing(data: page.drawingData) {
            canvasView.drawing = drawing
        }

        canvasView.layer.shadowColor = UIColor.black.cgColor
        canvasView.layer.shadowOpacity = Float(Design.Shadow.page.color)
        canvasView.layer.shadowOffset = CGSize(width: Design.Shadow.page.x, height: Design.Shadow.page.y)
        canvasView.layer.shadowRadius = Design.Shadow.page.radius

        let xOffset = (containerWidth - pageW) / 2
        let yOffset = gap + CGFloat(index) * (pageH + gap)
        canvasView.frame = CGRect(x: xOffset, y: yOffset, width: pageW, height: pageH)
        return canvasView
    }

    private func applyPendingScroll(_ pendingScroll: inout PagedCanvasContainer.ScrollAfterRebuild, pageH: CGFloat, gap: CGFloat, pageCount: Int) {
        guard let scrollView = scrollView else { return }
        let action = pendingScroll
        pendingScroll = .none

        let target: CGPoint
        switch action {
        case .none:
            return
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
        let bounds = scrollView.bounds.size
        let content = scrollView.contentSize

        containerView.center = CGPoint(
            x: content.width / 2 + max(0, (bounds.width - content.width) / 2),
            y: content.height / 2 + max(0, (bounds.height - content.height) / 2)
        )
    }

    func updateCurrentPage(pages: [Page], onCurrentPageChanged: ((Int) -> Void)?) {
        guard let scrollView = scrollView else { return }
        let centerY = (scrollView.contentOffset.y + scrollView.bounds.height / 2) / scrollView.zoomScale
        let pageH = PageConstants.pageHeight
        let gap = PageConstants.pageGap
        let pageIndex = max(0, Int((centerY - gap) / (pageH + gap)))
        onCurrentPageChanged?(min(pageIndex, max(0, pages.count - 1)))
    }
}
