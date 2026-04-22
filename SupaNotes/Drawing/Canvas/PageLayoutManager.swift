import UIKit

/// Owns geometry + page view rebuild logic for the multipage canvas.
final class PageLayoutManager {
    struct ViewportState {
        let pageIndex: Int
        let pageAnchor: CGPoint
        let anchorInScrollView: CGPoint
        let zoomScale: CGFloat
    }

    weak var scrollView: UIScrollView?
    weak var containerView: UIView?
    var canvasViews: [ExcalidrawPageCanvasView] = []
    var hasCompletedInitialLayout = false

    private let pageWidth = PageConstants.pageWidth
    private let pageHeight = PageConstants.pageHeight
    private let pageGap = PageConstants.pageGap

    func rebuildPages(
        pages: [Page],
        toolStyle: ExcalidrawToolStyle,
        interactionDelegate: ExcalidrawPageCanvasInteractionDelegate,
        pullController: PullToAddController,
        pendingScroll: inout PagedCanvasContainer.ScrollAfterRebuild,
        viewport: ViewportState?,
        onUndoManagerReady: @escaping (UndoManager?) -> Void,
        onPageMutated: @escaping () -> Void
    ) {
        guard let containerView, let scrollView else { return }

        let sortedPages = pages.sorted { $0.orderIndex < $1.orderIndex }
        let containerWidth = PageLayout.containerWidth(pageW: pageWidth, gap: pageGap, scrollWidth: scrollView.bounds.width)
        let totalSize = CGSize(
            width: containerWidth,
            height: CGFloat(sortedPages.count) * pageHeight + CGFloat(max(0, sortedPages.count - 1)) * pageGap + pageGap * 2
        )
        let pageFrames = PageLayout.pageFrames(
            count: sortedPages.count,
            pageW: pageWidth,
            pageH: pageHeight,
            gap: pageGap,
            containerWidth: containerWidth
        )

        UIView.performWithoutAnimation {
            canvasViews.forEach { $0.removeFromSuperview() }
            canvasViews.removeAll()

            containerView.bounds.size = totalSize

            canvasViews = pageFrames.enumerated().map { index, frame in
                let canvas = Self.makeCanvasView(
                    page: sortedPages[index],
                    index: index,
                    frame: frame,
                    toolStyle: toolStyle,
                    interactionDelegate: interactionDelegate,
                    onPageMutated: onPageMutated
                )
                containerView.addSubview(canvas)
                return canvas
            }

            if let viewport {
                restoreViewport(viewport, containerSize: totalSize)
            } else {
                scrollView.contentSize = PageLayout.scrollContentSize(containerSize: totalSize, zoomScale: scrollView.zoomScale)
                centerContainerIfNeeded()
            }

            containerView.layoutIfNeeded()
            scrollView.layoutIfNeeded()
        }

        pullController.setupIndicators(in: scrollView)
        applyPendingScroll(&pendingScroll, pageCount: sortedPages.count)
        centerContainerIfNeeded()

        if let first = canvasViews.first {
            DispatchQueue.main.async {
                onUndoManagerReady(first.undoManagerForPage)
            }
        }
    }

    private func restoreViewport(_ viewport: ViewportState, containerSize: CGSize) {
        guard let scrollView, let containerView else { return }

        let zoomScale = min(Design.Zoom.max, max(Design.Zoom.min, viewport.zoomScale))
        scrollView.zoomScale = zoomScale
        scrollView.contentSize = PageLayout.scrollContentSize(containerSize: containerSize, zoomScale: zoomScale)
        centerContainerIfNeeded()

        let pageFrame = PageLayout.pageFrame(
            index: viewport.pageIndex,
            pageW: pageWidth,
            pageH: pageHeight,
            gap: pageGap,
            containerWidth: containerSize.width
        )
        let anchorInContainer = CGPoint(
            x: pageFrame.minX + viewport.pageAnchor.x,
            y: pageFrame.minY + viewport.pageAnchor.y
        )
        let targetOffset = CGPoint(
            x: containerView.frame.minX + anchorInContainer.x * zoomScale - viewport.anchorInScrollView.x,
            y: containerView.frame.minY + anchorInContainer.y * zoomScale - viewport.anchorInScrollView.y
        )
        scrollView.contentOffset = clampedContentOffset(targetOffset)
    }

    private func clampedContentOffset(_ offset: CGPoint) -> CGPoint {
        guard let scrollView else { return offset }
        let maxX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
        let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        return CGPoint(x: min(max(0, offset.x), maxX), y: min(max(0, offset.y), maxY))
    }

    func captureViewportState(
        pages: [Page],
        anchorInScrollView: CGPoint? = nil,
        allowOutsidePageAnchor: Bool = false
    ) -> ViewportState? {
        guard let scrollView, let containerView, !pages.isEmpty else { return nil }

        let zoomScale = max(scrollView.zoomScale, 0.001)
        let anchor = anchorInScrollView ?? CGPoint(x: scrollView.bounds.width / 2, y: scrollView.bounds.height / 2)
        let anchorInScrollContent = CGPoint(
            x: scrollView.contentOffset.x + anchor.x,
            y: scrollView.contentOffset.y + anchor.y
        )
        let anchorInContainer = CGPoint(
            x: (anchorInScrollContent.x - containerView.frame.minX) / zoomScale,
            y: (anchorInScrollContent.y - containerView.frame.minY) / zoomScale
        )

        let frames = (0 ..< pages.count).map {
            PageLayout.pageFrame(index: $0, pageW: pageWidth, pageH: pageHeight, gap: pageGap, containerWidth: containerView.bounds.width)
        }
        let pageIndex = frames.enumerated().min { lhs, rhs in
            distanceToFrame(anchorInContainer, frame: lhs.element) < distanceToFrame(anchorInContainer, frame: rhs.element)
        }?.offset ?? 0

        let frame = frames[pageIndex]
        let pageAnchor = CGPoint(
            x: allowOutsidePageAnchor ? anchorInContainer.x - frame.minX : frame.width / 2,
            y: allowOutsidePageAnchor ? anchorInContainer.y - frame.minY : min(max(0, anchorInContainer.y - frame.minY), frame.height)
        )

        return ViewportState(pageIndex: pageIndex, pageAnchor: pageAnchor, anchorInScrollView: anchor, zoomScale: zoomScale)
    }

    private func distanceToFrame(_ point: CGPoint, frame: CGRect) -> CGFloat {
        let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
        let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
        return dx * dx + dy * dy
    }

    private static func makeCanvasView(
        page: Page,
        index: Int,
        frame: CGRect,
        toolStyle: ExcalidrawToolStyle,
        interactionDelegate: ExcalidrawPageCanvasInteractionDelegate,
        onPageMutated: @escaping () -> Void
    ) -> ExcalidrawPageCanvasView {
        let canvas = ExcalidrawPageCanvasView(page: page, frame: frame, toolStyle: toolStyle, onPageMutated: onPageMutated)
        canvas.tag = index
        canvas.interactionDelegate = interactionDelegate

        canvas.layer.shadowColor = UIColor.black.cgColor
        canvas.layer.shadowOpacity = Float(Design.Shadow.page.color)
        canvas.layer.shadowOffset = CGSize(width: Design.Shadow.page.x, height: Design.Shadow.page.y)
        canvas.layer.shadowRadius = Design.Shadow.page.radius
        return canvas
    }

    private func applyPendingScroll(_ pendingScroll: inout PagedCanvasContainer.ScrollAfterRebuild, pageCount: Int) {
        guard let scrollView, let containerView else { return }

        let action = pendingScroll
        pendingScroll = .none

        let preservedX = min(
            max(0, scrollView.contentOffset.x),
            max(0, scrollView.contentSize.width - scrollView.bounds.width)
        )

        let target: CGPoint
        switch action {
        case .none:
            return
        case .scrollToFirst:
            target = CGPoint(x: preservedX, y: 0)
        case .scrollToLast:
            let lastPageY = pageGap + CGFloat(pageCount - 1) * (pageHeight + pageGap)
            let targetY = max(0, (containerView.frame.minY + lastPageY) * scrollView.zoomScale - 20)
            let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
            target = CGPoint(x: preservedX, y: min(targetY, maxY))
        }

        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) {
            scrollView.contentOffset = target
        }
    }

    func centerContainerIfNeeded() {
        guard let scrollView, let containerView else { return }
        containerView.frame.origin = PageLayout.centeringOrigin(
            contentSize: containerView.frame.size,
            scrollBounds: scrollView.bounds.size
        )
    }

    func scrollToPage(index: Int) {
        guard let scrollView, let containerView, canvasViews.indices.contains(index) else { return }

        let y = pageGap + CGFloat(index) * (pageHeight + pageGap)
        let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        let targetY = min(max(0, (containerView.frame.minY + y) * scrollView.zoomScale - 20), maxY)

        UIView.animate(withDuration: 0.3) {
            scrollView.contentOffset = CGPoint(x: 0, y: targetY)
        }
    }

    func updateCurrentPage(pages: [Page], onCurrentPageChanged: ((Int) -> Void)?) {
        guard let scrollView, let containerView else { return }

        let centerY = (scrollView.contentOffset.y + scrollView.bounds.height / 2) / max(scrollView.zoomScale, 0.001) - containerView.frame.minY
        let pageIndex = max(0, Int((centerY - pageGap) / (pageHeight + pageGap)))
        onCurrentPageChanged?(min(pageIndex, max(0, pages.count - 1)))
    }
}
