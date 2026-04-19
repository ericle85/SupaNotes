import UIKit
import PencilKit

class PageLayoutManager {
    weak var scrollView: UIScrollView?
    weak var containerView: UIView?
    var canvasViews: [PKCanvasView] = []
    var hasCompletedInitialLayout = false

    /// This method completely recreates all page views.
    /// 
    /// Why do we do this instead of just updating existing ones?
    /// 1. PencilKit's PKCanvasView is complex and doesn't always handle frame changes well while zoomed.
    /// 2. Rebuilding ensures that the stack of pages always matches the SwiftData state perfectly.
    /// 3. It simplifies the math for positioning pages in a large, zoomable scroll view.
    func rebuildPages(
        pages: [Page],
        tool: PKTool,
        delegate: PKCanvasViewDelegate,
        pullController: PullToAddController,
        pendingScroll: inout PagedCanvasContainer.ScrollAfterRebuild,
        onUndoManagerReady: @escaping (UndoManager?) -> Void
    ) {
        guard let containerView = containerView, let scrollView = scrollView else { return }

        // If we are about to scroll, reset zoom to 1:1 first to make math easier
        if pendingScroll != .none {
            scrollView.zoomScale = 1.0 / PageConstants.renderScale
        }

        // Clean up old views
        canvasViews.forEach { $0.removeFromSuperview() }
        canvasViews.removeAll()

        // Calculate layout
        let sortedPages = pages.sorted { $0.orderIndex < $1.orderIndex }
        let width = PageConstants.internalWidth
        let height = PageConstants.internalHeight
        let spacing = PageConstants.internalGap
        
        let totalSize = PageLayout.containerSize(
            pageCount: sortedPages.count,
            pageW: width,
            pageH: height,
            gap: spacing,
            scrollWidth: scrollView.bounds.width
        )

        // Set bounds.size (not frame) so we don't clobber a live zoom transform.
        containerView.bounds.size = totalSize
        scrollView.contentSize = PageLayout.scrollContentSize(containerSize: totalSize, zoomScale: scrollView.zoomScale)

        // Create and add new canvas views for each page
        canvasViews = PageLayout.pageFrames(count: sortedPages.count, pageW: width, pageH: height, gap: spacing, containerWidth: totalSize.width)
            .enumerated()
            .map { index, frame in
                let canvas = Self.makeCanvasView(page: sortedPages[index], index: index, frame: frame, tool: tool, delegate: delegate)
                containerView.addSubview(canvas)
                return canvas
            }

        centerContainerIfNeeded()
        pullController.setupIndicators(in: scrollView)
        applyPendingScroll(&pendingScroll, pageH: height, gap: spacing, pageCount: sortedPages.count)

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

        if let image = PDFService.imageForPage(page) {
            let bg = UIImageView(image: image)
            bg.contentMode = .scaleToFill
            bg.frame = canvasView.bounds
            bg.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            canvasView.insertSubview(bg, at: 0)
            canvasView.isOpaque = false
            canvasView.backgroundColor = .clear
        }

        if let drawing = DrawingScaleNormalizer.normalizedDrawing(for: page) {
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
