import Testing
import UIKit
import SwiftUI
@testable import SupaNotes

// Tests for the view recycling system that keeps only a few DrawingCanvasView
// instances alive as the user scrolls through many pages.
@Suite struct PageRecyclerTests {

    // Each page is 612×792 with 24pt gaps — matches the standard layout tests.
    private let pageSize = CGSize(width: 612, height: 792)
    private let gap: CGFloat = 24

    // MARK: - Helpers

    // Build a recycler with N dummy pages and pre-computed frames.
    private func makeRecycler(
        pageCount: Int,
        bufferCount: Int = 1
    ) -> (PageRecycler, [CGRect]) {
        let recycler = PageRecycler(bufferCount: bufferCount)
        let sizes = Array(repeating: pageSize, count: pageCount)
        let containerWidth = PageLayout.getCanvasWidth(
            pageSizes: sizes, gap: gap, scrollWidth: 800
        )
        let frames = PageLayout.getPageFramesAsCGRects(
            pageSizes: sizes, gap: gap, containerWidth: containerWidth
        )
        let pages = (0..<pageCount).map { i in
            let p = Page()
            p.orderIndex = i
            return p
        }
        recycler.configure(sortedPages: pages, pageFrames: frames)

        // Stub canvas factory — returns a plain UIView-sized DrawingCanvasView stand-in.
        // We only need the tag and frame for recycler tests.
        recycler.createCanvas = { page, frame in
            // Minimal init — page + frame + default tool style.
            DrawingCanvasView(
                page: page, frame: frame,
                toolStyle: ToolStyle(selectedTool: .pen, selectedColor: .black, penWidth: 2, eraserWidth: 10),
                onPageMutated: {}
            )
        }
        return (recycler, frames)
    }

    // Build a visible rect that covers pages at the given indices.
    private func visibleRect(covering indices: Range<Int>, frames: [CGRect]) -> CGRect {
        let top = frames[indices.lowerBound].minY
        let bottom = frames[indices.upperBound - 1].maxY
        return CGRect(x: 0, y: top, width: 800, height: bottom - top)
    }

    // MARK: - configure

    // 1.1 — configure stores pages and frames.
    @Test func configure_storesData() {
        let (recycler, frames) = makeRecycler(pageCount: 5)
        #expect(recycler.sortedPages.count == 5)
        #expect(recycler.pageFrames.count == frames.count)
    }

    // MARK: - averagePageHeight

    // 2.1 — Average of uniform pages is the page height itself.
    @Test func averagePageHeight_uniformPages() {
        let (recycler, _) = makeRecycler(pageCount: 3)
        #expect(recycler.averagePageHeight() == pageSize.height)
    }

    // 2.2 — Empty pages returns 0 (or a safe default).
    @Test func averagePageHeight_empty() {
        let recycler = PageRecycler()
        #expect(recycler.averagePageHeight() == 0)
    }

    // MARK: - indicesInRect

    // 3.1 — Rect covering first two pages returns {0, 1}.
    @Test func indicesInRect_firstTwoPages() {
        let (recycler, frames) = makeRecycler(pageCount: 10)
        let rect = visibleRect(covering: 0..<2, frames: frames)
        #expect(recycler.indicesInRect(rect) == Set([0, 1]))
    }

    // 3.2 — Rect covering middle pages.
    @Test func indicesInRect_middlePages() {
        let (recycler, frames) = makeRecycler(pageCount: 10)
        let rect = visibleRect(covering: 4..<6, frames: frames)
        #expect(recycler.indicesInRect(rect) == Set([4, 5]))
    }

    // 3.3 — Rect beyond all pages returns empty.
    @Test func indicesInRect_beyondContent() {
        let (recycler, frames) = makeRecycler(pageCount: 3)
        let farBelow = CGRect(x: 0, y: frames.last!.maxY + 1000, width: 800, height: 500)
        #expect(recycler.indicesInRect(farBelow).isEmpty)
    }

    // MARK: - updateActiveWindow

    // 4.1 — Viewing pages 0-1 with buffer=1 activates pages 0, 1, 2.
    @Test func updateActiveWindow_initialView() {
        let (recycler, frames) = makeRecycler(pageCount: 10)
        let container = UIView()
        let rect = visibleRect(covering: 0..<2, frames: frames)
        recycler.updateActiveWindow(visibleRect: rect, containerView: container)
        let activeIndices = Set(recycler.activeViews.keys)
        // Pages 0, 1 visible + page 2 as buffer below.
        #expect(activeIndices.contains(0))
        #expect(activeIndices.contains(1))
        #expect(activeIndices.contains(2))
        // Should NOT have page 5+.
        #expect(!activeIndices.contains(5))
    }

    // 4.2 — Scrolling removes old pages and adds new ones.
    @Test func updateActiveWindow_scrollRemovesAndAdds() {
        let (recycler, frames) = makeRecycler(pageCount: 20)
        let container = UIView()

        // Start viewing pages 0-1.
        let rect1 = visibleRect(covering: 0..<2, frames: frames)
        recycler.updateActiveWindow(visibleRect: rect1, containerView: container)
        let firstSet = Set(recycler.activeViews.keys)
        #expect(firstSet.contains(0))

        // Scroll to pages 10-11.
        let rect2 = visibleRect(covering: 10..<12, frames: frames)
        recycler.updateActiveWindow(visibleRect: rect2, containerView: container)
        let secondSet = Set(recycler.activeViews.keys)
        // Page 0 should be gone.
        #expect(!secondSet.contains(0))
        // Pages 10, 11 should be active.
        #expect(secondSet.contains(10))
        #expect(secondSet.contains(11))
    }

    // 4.3 — Removed canvases are removed from the container's subviews.
    @Test func updateActiveWindow_removesSubviews() {
        let (recycler, frames) = makeRecycler(pageCount: 10)
        let container = UIView()

        // Activate first pages.
        let rect1 = visibleRect(covering: 0..<1, frames: frames)
        recycler.updateActiveWindow(visibleRect: rect1, containerView: container)
        let initialSubviewCount = container.subviews.count

        // Scroll far away.
        let rect2 = visibleRect(covering: 8..<10, frames: frames)
        recycler.updateActiveWindow(visibleRect: rect2, containerView: container)

        // Old subviews should be removed, new ones added.
        // Total subview count should stay roughly the same (buffer zone sized).
        #expect(container.subviews.count <= initialSubviewCount + 2)
        #expect(container.subviews.count > 0)
    }

    // 4.4 — willRemoveCanvas fires for each removed canvas.
    @Test func updateActiveWindow_firesWillRemoveCallback() {
        let (recycler, frames) = makeRecycler(pageCount: 10)
        let container = UIView()
        var removedTags: [Int] = []
        recycler.willRemoveCanvas = { (canvas: DrawingCanvasView) in removedTags.append(canvas.tag) }

        // Activate pages 0-1.
        let rect1 = visibleRect(covering: 0..<2, frames: frames)
        recycler.updateActiveWindow(visibleRect: rect1, containerView: container)

        // Scroll to pages 8-9 — original pages should be removed.
        let rect2 = visibleRect(covering: 8..<10, frames: frames)
        recycler.updateActiveWindow(visibleRect: rect2, containerView: container)
        #expect(!removedTags.isEmpty)
    }

    // 4.5 — Large document still keeps only a small active window.
    @Test func updateActiveWindow_largeDocument_keepsWindowBounded() {
        let (recycler, frames) = makeRecycler(pageCount: 200, bufferCount: 1)
        let container = UIView()

        // Simulate viewing two pages deep in a long document.
        let rect = visibleRect(covering: 50..<52, frames: frames)
        recycler.updateActiveWindow(visibleRect: rect, containerView: container)

        // Expected active set is visible pages plus one page of buffer above/below.
        let activeIndices = Set(recycler.activeViews.keys)
        #expect(activeIndices == Set([49, 50, 51, 52]))
        #expect(recycler.activeViews.count == 4)
    }

    // 4.6 — Re-applying the same visible rect should not duplicate views.
    @Test func updateActiveWindow_sameRect_isStable() {
        let (recycler, frames) = makeRecycler(pageCount: 40, bufferCount: 1)
        let container = UIView()
        let rect = visibleRect(covering: 10..<12, frames: frames)

        recycler.updateActiveWindow(visibleRect: rect, containerView: container)
        let firstActiveIndices = Set(recycler.activeViews.keys)
        let firstSubviewCount = container.subviews.count

        // Run again with same viewport to verify stable/repeatable behavior.
        recycler.updateActiveWindow(visibleRect: rect, containerView: container)
        let secondActiveIndices = Set(recycler.activeViews.keys)
        let secondSubviewCount = container.subviews.count

        #expect(firstActiveIndices == secondActiveIndices)
        #expect(firstSubviewCount == secondSubviewCount)
    }

    // MARK: - removeAll

    // 5.1 — removeAll clears all active views.
    @Test func removeAll_clearsEverything() {
        let (recycler, frames) = makeRecycler(pageCount: 5)
        let container = UIView()
        let rect = visibleRect(covering: 0..<3, frames: frames)
        recycler.updateActiveWindow(visibleRect: rect, containerView: container)
        #expect(!recycler.activeViews.isEmpty)

        recycler.removeAll()
        #expect(recycler.activeViews.isEmpty)
    }

    // 5.2 — removeAll fires willRemoveCanvas for each view.
    @Test func removeAll_firesCallbacks() {
        let (recycler, frames) = makeRecycler(pageCount: 5)
        let container = UIView()
        var removedCount = 0
        recycler.willRemoveCanvas = { (_: DrawingCanvasView) in removedCount += 1 }

        let rect = visibleRect(covering: 0..<3, frames: frames)
        recycler.updateActiveWindow(visibleRect: rect, containerView: container)
        let activeCount = recycler.activeViews.count

        recycler.removeAll()
        #expect(removedCount == activeCount)
    }

    // MARK: - Queries

    // 6.1 — allActiveCanvases returns sorted by tag.
    @Test func allActiveCanvases_sortedByTag() {
        let (recycler, frames) = makeRecycler(pageCount: 10)
        let container = UIView()
        let rect = visibleRect(covering: 3..<5, frames: frames)
        recycler.updateActiveWindow(visibleRect: rect, containerView: container)

        let tags = recycler.allActiveCanvases.map { $0.tag }
        #expect(tags == tags.sorted())
    }

    // 6.2 — canvas(at:) returns the correct view.
    @Test func canvasAtIndex_returnsCorrectView() {
        let (recycler, frames) = makeRecycler(pageCount: 5)
        let container = UIView()
        let rect = visibleRect(covering: 1..<3, frames: frames)
        recycler.updateActiveWindow(visibleRect: rect, containerView: container)

        // An active page should be found.
        let canvas = recycler.canvas(at: 1)
        #expect(canvas != nil)
        #expect(canvas?.tag == 1)

        // A far-away page should not.
        #expect(recycler.canvas(at: 4) == nil)
    }

    // MARK: - Edge cases

    // 7.1 — Single page note.
    @Test func singlePage() {
        let (recycler, frames) = makeRecycler(pageCount: 1)
        let container = UIView()
        let rect = visibleRect(covering: 0..<1, frames: frames)
        recycler.updateActiveWindow(visibleRect: rect, containerView: container)
        #expect(recycler.activeViews.count == 1)
        #expect(recycler.activeViews[0] != nil)
    }

    // 7.2 — Empty pages array does nothing.
    @Test func emptyPages() {
        let recycler = PageRecycler()
        let container = UIView()
        recycler.updateActiveWindow(
            visibleRect: CGRect(x: 0, y: 0, width: 800, height: 600),
            containerView: container
        )
        #expect(recycler.activeViews.isEmpty)
    }

    // 7.3 — Partial overlap should still include the page index.
    @Test func indicesInRect_partialOverlap() {
        let (recycler, frames) = makeRecycler(pageCount: 8)

        // Build a rect that overlaps only the lower portion of page 3.
        let page3 = frames[3]
        let partial = CGRect(x: 0, y: page3.midY, width: 800, height: 10)

        #expect(recycler.indicesInRect(partial).contains(3))
    }
}
