import Testing
import UIKit
import PencilKit
@testable import SupaNotes

/// Exercises `PageLayoutManager.centerContainerIfNeeded` against a real
/// UIScrollView + container. Uses display-scale sizes (post-zoom) since
/// centering math is scale-invariant. Regression guard for: adding a page
/// must not snap pages to the left edge.
@MainActor
struct PageLayoutManagerIntegrationTests {

    /// A tiny stand-in object for PencilKit's delegate.
    /// The layout manager needs "some delegate" when it builds canvases,
    /// but these tests do not care about delegate callbacks.
    private final class CanvasDelegate: NSObject, PKCanvasViewDelegate {}

    // Display-scale page geometry (what the user sees after zoom-out).
    private let pageW = PageConstants.pageWidth
    private let pageH = PageConstants.pageHeight
    private let gap = PageConstants.pageGap

    private func makeStack(scrollBounds: CGSize) -> (UIScrollView, UIView, PageLayoutManager) {
        // Build the smallest real scrolling setup that the layout manager expects:
        // one scroll view, one container inside it, and the manager wired to both.
        let scroll = UIScrollView(frame: CGRect(origin: .zero, size: scrollBounds))
        let container = UIView()
        scroll.addSubview(container)
        let manager = PageLayoutManager()
        manager.scrollView = scroll
        manager.containerView = container
        return (scroll, container, manager)
    }

    @MainActor
    private func rebuild(
        manager: PageLayoutManager,
        pages: [Page],
        scroll: UIScrollView,
        pendingScroll: inout PagedCanvasContainer.ScrollAfterRebuild,
        presentationBand: PresentationZoomBand = .baseline,
        viewport: PageLayoutManager.ViewportState? = nil
    ) {
        // This helper performs the same kind of rebuild the app does in real use.
        // Using one helper keeps the tests short and makes the setup easier to follow.
        _ = scroll // retain
        manager.rebuildPages(
            pages: pages,
            tool: PKInkingTool(.pen, color: .black, width: 5),
            delegate: CanvasDelegate(),
            pullController: PullToAddController(),
            pendingScroll: &pendingScroll,
            presentationBand: presentationBand,
            viewport: viewport,
            onUndoManagerReady: { _ in }
        )
    }

    private func pageMidInScroll(container: UIView, containerWidth: CGFloat) -> CGFloat {
        let page0 = PageLayout.pageFrame(index: 0, pageW: pageW, pageH: pageH, gap: gap, containerWidth: containerWidth)
        return container.frame.origin.x + page0.midX
    }

    // MARK: - centerContainerIfNeeded

    @Test("Single page centers horizontally", arguments: [CGSize(width: 820, height: 1180), CGSize(width: 1180, height: 820), CGSize(width: 1024, height: 768)])
    func singlePage_centered(scrollBounds: CGSize) {
        let (scroll, container, manager) = makeStack(scrollBounds: scrollBounds)
        _ = scroll // retain — manager.scrollView is weak
        let size = PageLayout.containerSize(pageCount: 1, pageW: pageW, pageH: pageH, gap: gap, scrollWidth: scrollBounds.width)
        container.bounds.size = size
        manager.centerContainerIfNeeded()

        #expect(abs(pageMidInScroll(container: container, containerWidth: size.width) - scrollBounds.width / 2) < 0.5)
    }

    @Test("Adding pages preserves horizontal centering", arguments: [1, 2, 3, 5, 10, 50])
    func addedPages_centered(pageCount: Int) {
        let scrollBounds = CGSize(width: 820, height: 1180)
        let (scroll, container, manager) = makeStack(scrollBounds: scrollBounds)
        _ = scroll // retain — manager.scrollView is weak
        let size = PageLayout.containerSize(pageCount: pageCount, pageW: pageW, pageH: pageH, gap: gap, scrollWidth: scrollBounds.width)
        container.bounds.size = size
        manager.centerContainerIfNeeded()

        #expect(abs(pageMidInScroll(container: container, containerWidth: size.width) - scrollBounds.width / 2) < 0.5)
    }

    // MARK: - regression: rebuild simulating add-page

    @Test("Simulated add-page rebuild does not shift centerX", arguments: [2, 3, 5, 10])
    func rebuildAfterAddPage_doesNotShiftCenterX(newCount: Int) {
        let scrollBounds = CGSize(width: 820, height: 1180)
        let (scroll, container, manager) = makeStack(scrollBounds: scrollBounds)
        _ = scroll // retain — manager.scrollView is weak

        let initial = PageLayout.containerSize(pageCount: 1, pageW: pageW, pageH: pageH, gap: gap, scrollWidth: scrollBounds.width)
        container.bounds.size = initial
        manager.centerContainerIfNeeded()
        let midBefore = pageMidInScroll(container: container, containerWidth: initial.width)

        // Simulate rebuildPages post-add: resize bounds (safe under transform), re-center.
        let after = PageLayout.containerSize(pageCount: newCount, pageW: pageW, pageH: pageH, gap: gap, scrollWidth: scrollBounds.width)
        container.bounds.size = after
        manager.centerContainerIfNeeded()
        let midAfter = pageMidInScroll(container: container, containerWidth: after.width)

        #expect(abs(midBefore - midAfter) < 0.5)
        #expect(abs(midAfter - scrollBounds.width / 2) < 0.5)
    }

    @Test("Zoom-band capture preserves off-page horizontal anchor")
    func captureViewportState_allowsOutsidePageAnchor_forBandSwitch() {
        let scrollBounds = CGSize(width: 820, height: 1180)
        let (scroll, _, manager) = makeStack(scrollBounds: scrollBounds)
        var pendingScroll: PagedCanvasContainer.ScrollAfterRebuild = .none
        let pages = [Page(orderIndex: 0)]

        // Start with one normal page on screen.
        rebuild(manager: manager, pages: pages, scroll: scroll, pendingScroll: &pendingScroll)

        let frame = try! #require(manager.canvasViews.first?.frame)
        // Pretend the user's pinch focus is slightly to the LEFT of the page,
        // in the dark gutter area rather than on the paper itself.
        let anchorInScrollView = CGPoint(x: frame.minX - 40, y: frame.midY)
        let viewport = try! #require(
            manager.captureViewportState(
                pages: pages,
                anchorInScrollView: anchorInScrollView,
                allowOutsidePageAnchor: true
            )
        )

        // For zoom-band switches we want to preserve that exact off-page focus point.
        // A negative X anchor means "the user's fingers were left of the page."
        #expect(viewport.pageAnchor.x < 0)
        // The on-screen pinch location itself should also be preserved exactly.
        #expect(abs(viewport.anchorInScrollView.x - anchorInScrollView.x) < 0.001)
    }

    @Test("Structural rebuild capture recenters horizontally")
    func captureViewportState_centersHorizontally_forStructuralRebuilds() {
        let scrollBounds = CGSize(width: 820, height: 1180)
        let (scroll, _, manager) = makeStack(scrollBounds: scrollBounds)
        var pendingScroll: PagedCanvasContainer.ScrollAfterRebuild = .none
        let pages = [Page(orderIndex: 0)]

        // Start with one normal page on screen.
        rebuild(manager: manager, pages: pages, scroll: scroll, pendingScroll: &pendingScroll)

        let frame = try! #require(manager.canvasViews.first?.frame)
        // Again, pretend the visible focus point is left of the page.
        let anchorInScrollView = CGPoint(x: frame.minX - 40, y: frame.midY)
        // For structural rebuilds, Y should stay tied to the same vertical place
        // on the page that the user was looking at.
        let containerOriginY = try! #require(manager.containerView?.frame.minY)
        let expectedPageAnchorY = anchorInScrollView.y - containerOriginY - frame.minY
        let viewport = try! #require(
            manager.captureViewportState(
                pages: pages,
                anchorInScrollView: anchorInScrollView
            )
        )

        // But for structural changes like adding/removing pages, we DO NOT want
        // to preserve empty gutter space horizontally. The page should stay centered.
        // So the captured X anchor should be reset to the page midpoint.
        #expect(abs(viewport.pageAnchor.x - PageConstants.pageWidth / 2) < 0.001)
        // The Y position should still track the same place vertically on the page.
        #expect(abs(viewport.pageAnchor.y - expectedPageAnchorY) < 0.001)
    }

    @Test("Scroll-to-last rebuild preserves horizontal offset")
    func rebuildWithPendingScroll_preservesHorizontalOffset() {
        let scrollBounds = CGSize(width: 820, height: 1180)
        let (scroll, _, manager) = makeStack(scrollBounds: scrollBounds)
        let pages = (0..<3).map { Page(orderIndex: $0) }
        var pendingScroll: PagedCanvasContainer.ScrollAfterRebuild = .none

        // Build an initial stack of pages.
        rebuild(manager: manager, pages: pages, scroll: scroll, pendingScroll: &pendingScroll)

        // Disable animations so the test can inspect the final scroll position immediately.
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(true) }

        // Pretend the user is already horizontally positioned away from zero.
        // This is the exact situation that used to break when swiping to add a page.
        scroll.contentOffset.x = 137
        pendingScroll = .scrollToLast
        // Rebuild as if a new page was added at the bottom.
        rebuild(manager: manager, pages: pages + [Page(orderIndex: 3)], scroll: scroll, pendingScroll: &pendingScroll)

        // The fix is: scrolling to the new bottom page should only change Y,
        // not throw away the user's current horizontal position.
        #expect(abs(scroll.contentOffset.x - 137) < 0.5)
    }

}
