import UIKit
import PencilKit

class PageLayoutManager {
    struct ViewportState {
        let logicalCenter: CGPoint
        let effectiveZoom: CGFloat
    }

    weak var scrollView: UIScrollView?
    weak var containerView: UIView?
    var canvasViews: [PKCanvasView] = []
    var hasCompletedInitialLayout = false
    private(set) var presentationBand: PresentationZoomBand = .baseline

    private var pageWidth: CGFloat { PageConstants.pageWidth * presentationBand.scale }
    private var pageHeight: CGFloat { PageConstants.pageHeight * presentationBand.scale }
    private var pageGap: CGFloat { PageConstants.pageGap * presentationBand.scale }

    /// This method completely recreates all page views.
    ///
    /// Why do we do this instead of just updating existing ones?
    /// 1. PencilKit's PKCanvasView is complex and doesn't always handle frame changes well while zoomed.
    /// 2. Rebuilding ensures that the stack of pages always matches the SwiftData state perfectly.
    /// 3. It lets us swap presentation scales without changing the stored drawing coordinates.
    func rebuildPages(
        pages: [Page],
        tool: PKTool,
        delegate: PKCanvasViewDelegate,
        pullController: PullToAddController,
        pendingScroll: inout PagedCanvasContainer.ScrollAfterRebuild,
        presentationBand: PresentationZoomBand,
        viewport: ViewportState?,
        onUndoManagerReady: @escaping (UndoManager?) -> Void
    ) {
        guard let containerView = containerView, let scrollView = scrollView else { return }
        self.presentationBand = presentationBand

        // Clean up old views
        canvasViews.forEach { $0.removeFromSuperview() }
        canvasViews.removeAll()

        // Calculate layout
        let sortedPages = pages.sorted { $0.orderIndex < $1.orderIndex }
        let width = pageWidth
        let height = pageHeight
        let spacing = pageGap

        let totalSize = PageLayout.containerSize(
            pageCount: sortedPages.count,
            pageW: width,
            pageH: height,
            gap: spacing,
            scrollWidth: scrollView.bounds.width
        )

        // Set bounds.size (not frame) so we don't clobber a live zoom transform.
        containerView.bounds.size = totalSize

        // Create and add new canvas views for each page
        canvasViews = PageLayout.pageFrames(count: sortedPages.count, pageW: width, pageH: height, gap: spacing, containerWidth: totalSize.width)
            .enumerated()
            .map { index, frame in
                let canvas = Self.makeCanvasView(
                    page: sortedPages[index],
                    index: index,
                    frame: frame,
                    tool: tool,
                    delegate: delegate,
                    presentationScale: presentationBand.scale
                )
                containerView.addSubview(canvas)
                return canvas
            }

        if let viewport {
            restoreViewport(viewport, containerSize: totalSize)
        } else {
            scrollView.contentSize = PageLayout.scrollContentSize(containerSize: totalSize, zoomScale: scrollView.zoomScale)
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

    private func restoreViewport(_ viewport: ViewportState, containerSize: CGSize) {
        guard let scrollView = scrollView, let containerView = containerView else { return }
        let zoomScale = clampedZoomScale(for: viewport.effectiveZoom)
        scrollView.zoomScale = zoomScale
        scrollView.contentSize = PageLayout.scrollContentSize(containerSize: containerSize, zoomScale: zoomScale)
        centerContainerIfNeeded()

        let centerInContainer = CGPoint(
            x: viewport.logicalCenter.x * presentationBand.scale,
            y: viewport.logicalCenter.y * presentationBand.scale
        )
        let targetOffset = CGPoint(
            x: (containerView.frame.minX + centerInContainer.x) * zoomScale - scrollView.bounds.width / 2,
            y: (containerView.frame.minY + centerInContainer.y) * zoomScale - scrollView.bounds.height / 2
        )
        scrollView.contentOffset = clampedContentOffset(targetOffset)
    }

    private func clampedZoomScale(for effectiveZoom: CGFloat) -> CGFloat {
        let zoomScale = effectiveZoom / max(presentationBand.scale, 0.001)
        return min(Design.Zoom.max, max(Design.Zoom.min, zoomScale))
    }

    private func clampedContentOffset(_ offset: CGPoint) -> CGPoint {
        guard let scrollView = scrollView else { return offset }
        let maxX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
        let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        return CGPoint(
            x: min(max(0, offset.x), maxX),
            y: min(max(0, offset.y), maxY)
        )
    }

    func captureViewportState() -> ViewportState? {
        guard let scrollView = scrollView, let containerView = containerView else { return nil }
        let zoomScale = max(scrollView.zoomScale, 0.001)
        let centerInScroll = CGPoint(
            x: scrollView.contentOffset.x + scrollView.bounds.width / 2,
            y: scrollView.contentOffset.y + scrollView.bounds.height / 2
        )
        let centerInContainer = CGPoint(
            x: centerInScroll.x / zoomScale - containerView.frame.minX,
            y: centerInScroll.y / zoomScale - containerView.frame.minY
        )
        let logicalCenter = CGPoint(
            x: centerInContainer.x / max(presentationBand.scale, 0.001),
            y: centerInContainer.y / max(presentationBand.scale, 0.001)
        )
        return ViewportState(
            logicalCenter: logicalCenter,
            effectiveZoom: presentationBand.scale * zoomScale
        )
    }

    func effectiveZoom() -> CGFloat {
        guard let scrollView = scrollView else { return presentationBand.scale }
        return presentationBand.scale * scrollView.zoomScale
    }

    func preferredPresentationBand() -> PresentationZoomBand {
        PresentationZoomBand.preferredBand(for: effectiveZoom())
    }

    private static func makeCanvasView(
        page: Page,
        index: Int,
        frame: CGRect,
        tool: PKTool,
        delegate: PKCanvasViewDelegate,
        presentationScale: CGFloat
    ) -> PKCanvasView {
        let canvasView = SupaCanvasView()
        canvasView.presentationScale = presentationScale
        canvasView.drawingPolicy = .pencilOnly
        canvasView.backgroundColor = page.template.backgroundColor
        canvasView.overrideUserInterfaceStyle = page.template.interfaceStyle
        canvasView.isScrollEnabled = false
        canvasView.tool = tool
        canvasView.tag = index
        canvasView.delegate = delegate
        canvasView.frame = frame

        if let image = PDFService.imageForPage(page) {
            let bg = UIImageView(image: image)
            bg.contentMode = .scaleToFill
            bg.frame = canvasView.bounds
            bg.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            canvasView.insertSubview(bg, at: 0)
            canvasView.isOpaque = false
            canvasView.backgroundColor = .clear
        }

        if let drawing = DrawingCoordinateSpace.presentationDrawing(for: page, presentationScale: presentationScale) {
            canvasView.drawing = drawing
        }

        canvasView.layer.shadowColor = UIColor.black.cgColor
        canvasView.layer.shadowOpacity = Float(Design.Shadow.page.color)
        canvasView.layer.shadowOffset = CGSize(width: Design.Shadow.page.x, height: Design.Shadow.page.y)
        canvasView.layer.shadowRadius = Design.Shadow.page.radius
        return canvasView
    }

    private func applyPendingScroll(_ pendingScroll: inout PagedCanvasContainer.ScrollAfterRebuild, pageH: CGFloat, gap: CGFloat, pageCount: Int) {
        guard let scrollView = scrollView, let containerView = containerView else { return }
        let action = pendingScroll
        pendingScroll = .none

        let target: CGPoint
        switch action {
        case .none: return
        case .scrollToFirst:
            target = .zero
        case .scrollToLast:
            let lastPageY = gap + CGFloat(pageCount - 1) * (pageH + gap)
            let targetY = max(0, (containerView.frame.minY + lastPageY) * scrollView.zoomScale - 20)
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
        guard let scrollView = scrollView, let containerView = containerView, canvasViews.indices.contains(index) else { return }
        let pageH = pageHeight
        let gap = pageGap
        let y = gap + CGFloat(index) * (pageH + gap)
        let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        let targetY = min(max(0, (containerView.frame.minY + y) * scrollView.zoomScale - 20), maxY)
        UIView.animate(withDuration: 0.3) {
            scrollView.contentOffset = CGPoint(x: 0, y: targetY)
        }
    }

    func updateCurrentPage(pages: [Page], onCurrentPageChanged: ((Int) -> Void)?) {
        guard let scrollView = scrollView, let containerView = containerView else { return }
        let centerY = (scrollView.contentOffset.y + scrollView.bounds.height / 2) / max(scrollView.zoomScale, 0.001) - containerView.frame.minY
        let pageH = pageHeight
        let gap = pageGap
        let pageIndex = max(0, Int((centerY - gap) / (pageH + gap)))
        onCurrentPageChanged?(min(pageIndex, max(0, pages.count - 1)))
    }
}
