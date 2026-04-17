import Testing
import UIKit
@testable import SupaNotes

/// Exercises `PageLayoutManager.centerContainerIfNeeded` against a real
/// UIScrollView + container. Uses display-scale sizes (post-zoom) since
/// centering math is scale-invariant. Regression guard for: adding a page
/// must not snap pages to the left edge.
@MainActor
struct PageLayoutManagerIntegrationTests {

    // Display-scale page geometry (what the user sees after zoom-out).
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

}
