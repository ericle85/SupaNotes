import Testing
import UIKit
@testable import SupaNotes

@MainActor
struct PageLayoutManagerIntegrationTests {
    private final class Observer: NSObject, ActionObserver {}

    private let pageW = PageConstants.pageWidth
    private let pageH = PageConstants.pageHeight
    private let gap = PageConstants.pageGap

    private func makeStack(scrollBounds: CGSize) -> (UIScrollView, UIView, PageLayoutManager) {
        let scroll = UIScrollView(frame: CGRect(origin: .zero, size: scrollBounds))
        let container = UIView()
        scroll.addSubview(container)
        let manager = PageLayoutManager()
        manager.scrollView = scroll
        manager.containerView = container
        return (scroll, container, manager)
    }

    private func rebuild(
        manager: PageLayoutManager,
        pages: [Page],
        pendingScroll: inout PagedCanvasContainer.ScrollAfterRebuild,
        viewport: PageLayoutManager.ViewportState? = nil
    ) {
        manager.rebuildPages(
            pages: pages,
            tool: .pen(color: .black, width: 5),
            observer: Observer(),
            pullController: PullToAddController(),
            pendingScroll: &pendingScroll,
            viewport: viewport,
            onUndoManagerReady: { _ in }
        )
    }

    private func pageMidInScroll(container: UIView, containerWidth: CGFloat) -> CGFloat {
        let page0 = PageLayout.pageFrame(index: 0, pageW: pageW, pageH: pageH, gap: gap, containerWidth: containerWidth)
        return container.frame.origin.x + page0.midX
    }

    @Test("Single page centers horizontally")
    func singlePageCentered() {
        let scrollBounds = CGSize(width: 820, height: 1180)
        let (_, container, manager) = makeStack(scrollBounds: scrollBounds)
        let size = PageLayout.containerSize(pageCount: 1, pageW: pageW, pageH: pageH, gap: gap, scrollWidth: scrollBounds.width)
        container.bounds.size = size
        manager.centerContainerIfNeeded()
        #expect(abs(pageMidInScroll(container: container, containerWidth: size.width) - scrollBounds.width / 2) < 0.5)
    }

    @Test("Structural rebuild capture recenters horizontally")
    func captureViewportStateCentersHorizontally() {
        let scrollBounds = CGSize(width: 820, height: 1180)
        let (scroll, _, manager) = makeStack(scrollBounds: scrollBounds)
        _ = scroll
        var pendingScroll: PagedCanvasContainer.ScrollAfterRebuild = .none
        let pages = [Page(orderIndex: 0)]

        rebuild(manager: manager, pages: pages, pendingScroll: &pendingScroll)

        let frame = try! #require(manager.canvasViews.first?.frame)
        let anchorInScrollView = CGPoint(x: frame.minX - 40, y: frame.midY)
        let containerOriginY = try! #require(manager.containerView?.frame.minY)
        let expectedPageAnchorY = anchorInScrollView.y - containerOriginY - frame.minY
        let viewport = try! #require(
            manager.captureViewportState(
                pages: pages,
                anchorInScrollView: anchorInScrollView
            )
        )

        #expect(abs(viewport.pageAnchor.x - PageConstants.pageWidth / 2) < 0.001)
        #expect(abs(viewport.pageAnchor.y - expectedPageAnchorY) < 0.001)
    }
}
