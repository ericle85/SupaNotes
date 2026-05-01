import Testing
import UIKit
import SwiftData
@testable import SupaNotes

// Tests for the single-canvas focus swap mechanism. Validates that the coordinator
// correctly reparents the live canvas and snapshots outgoing pages.
@MainActor
@Suite struct SingleCanvasFocusTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Note.self, Page.self, Folder.self, configurations: config)
    }

    private func makePages(in context: ModelContext, count: Int) throws -> [Page] {
        let note = Note(title: "Focus Test Note")
        context.insert(note)
        note.pages = []
        for i in 0..<count {
            let page = Page(orderIndex: i)
            context.insert(page)
            page.note = note
        }
        try context.save()
        return note.sortedPages
    }

    private func makeHarness(
        pages: [Page],
        scrollSize: CGSize = CGSize(width: 900, height: 1000)
    ) -> (
        coordinator: MultipageCanvasContainer.Coordinator,
        scrollView: UIScrollView,
        containerView: UIView
    ) {
        let coordinator = MultipageCanvasContainer.Coordinator(
            pages: pages,
            toolbar: ToolbarState(),
            onUndoManagerReady: { _ in },
            onPencilDoubleTap: nil,
            onCurrentPageChanged: nil,
            addPage: {},
            addPageAbove: nil,
            onPageMutated: {}
        )
        let scrollView = UIScrollView(frame: CGRect(origin: .zero, size: scrollSize))
        scrollView.bounds = CGRect(origin: .zero, size: scrollSize)
        scrollView.zoomScale = 1
        let containerView = UIView()
        scrollView.addSubview(containerView)
        coordinator.scrollView = scrollView
        coordinator.containerView = containerView
        return (coordinator, scrollView, containerView)
    }

    // Count DrawingCanvasView instances across all slots.
    private func canvasCount(in containerView: UIView) -> Int {
        containerView.subviews.flatMap { $0.subviews.compactMap { $0 as? DrawingCanvasView } }.count
    }

    // MARK: - Tests

    // After rebuild, live canvas on page 0 + adjacent display canvas on page 1.
    @Test func rebuild_mountsCanvasOnPage0() throws {
        let container = try makeContainer()
        let pages = try makePages(in: container.mainContext, count: 5)
        let harness = makeHarness(pages: pages)

        harness.coordinator.rebuildPages(pages: pages, toolbar: ToolbarState(), viewport: nil)

        #expect(harness.coordinator.canvasPageIndex == 0)
        #expect(harness.coordinator.liveCanvas != nil)
        // 1 live + 1 adjacent (page 1; no page -1).
        #expect(canvasCount(in: harness.containerView) == 2)
        #expect(harness.coordinator.adjacentCanvases[1] != nil)
    }

    // Scroll-settle to a different page swaps focus.
    @Test func scrollSettle_swapsFocus() throws {
        let container = try makeContainer()
        let pages = try makePages(in: container.mainContext, count: 20)
        let harness = makeHarness(pages: pages)

        harness.coordinator.rebuildPages(pages: pages, toolbar: ToolbarState(), viewport: nil)
        #expect(harness.coordinator.canvasPageIndex == 0)

        // Scroll far enough that currentPageIndex lands on a later page.
        let targetFrame = harness.coordinator.pageFrames[10]
        harness.scrollView.contentOffset = CGPoint(x: 0, y: targetFrame.midY - harness.scrollView.bounds.height / 2)
        harness.coordinator.scrollViewDidEndDecelerating(harness.scrollView)

        // Canvas should have moved away from page 0.
        #expect(harness.coordinator.canvasPageIndex != 0)
        // 1 live + up to 2 adjacent.
        #expect(canvasCount(in: harness.containerView) <= 3)
    }

    // Outgoing page should receive a bitmap snapshot after focus swap.
    @Test func focusSwap_snapshotsOutgoingPage() throws {
        let container = try makeContainer()
        let pages = try makePages(in: container.mainContext, count: 20)
        let harness = makeHarness(pages: pages)

        harness.coordinator.rebuildPages(pages: pages, toolbar: ToolbarState(), viewport: nil)

        // Trigger focus swap to page 10.
        let targetFrame = harness.coordinator.pageFrames[10]
        harness.scrollView.contentOffset = CGPoint(x: 0, y: targetFrame.midY - harness.scrollView.bounds.height / 2)
        harness.coordinator.scrollViewDidEndDecelerating(harness.scrollView)

        // The outgoing slot (page 0) should now have a bitmap.
        let slot0 = harness.coordinator.slots[0]
        #expect(slot0.bitmap != nil)
    }

    // Canvas slot should NOT have a bitmap (canvas covers it).
    @Test func canvasSlot_hasNoBitmap() throws {
        let container = try makeContainer()
        let pages = try makePages(in: container.mainContext, count: 5)
        let harness = makeHarness(pages: pages)

        harness.coordinator.rebuildPages(pages: pages, toolbar: ToolbarState(), viewport: nil)

        let canvasIndex = harness.coordinator.canvasPageIndex
        #expect(harness.coordinator.slots[canvasIndex].bitmap == nil)
    }

    // Single-page note: canvas stays on page 0, no swaps needed.
    @Test func singlePage_canvasStaysOnPage0() throws {
        let container = try makeContainer()
        let pages = try makePages(in: container.mainContext, count: 1)
        let harness = makeHarness(pages: pages)

        harness.coordinator.rebuildPages(pages: pages, toolbar: ToolbarState(), viewport: nil)
        harness.coordinator.scrollViewDidEndDecelerating(harness.scrollView)

        #expect(harness.coordinator.canvasPageIndex == 0)
        #expect(canvasCount(in: harness.containerView) == 1)
    }

    // Settling on the same page as current canvas should not recreate it.
    @Test func settleOnSamePage_noSwap() throws {
        let container = try makeContainer()
        let pages = try makePages(in: container.mainContext, count: 5)
        let harness = makeHarness(pages: pages)

        harness.coordinator.rebuildPages(pages: pages, toolbar: ToolbarState(), viewport: nil)
        let firstCanvas = harness.coordinator.liveCanvas

        // Scroll within page 0 and settle.
        harness.scrollView.contentOffset = CGPoint(x: 0, y: 10)
        harness.coordinator.scrollViewDidEndDecelerating(harness.scrollView)

        // Same canvas instance — no swap occurred.
        #expect(harness.coordinator.liveCanvas === firstCanvas)
    }

    // MARK: - Adjacent rendering

    // 4 pages, active on page 0 → 2 canvases (live + adjacent page 1).
    // Jump to page 2 (index 2) → 3 canvases (live + adjacent pages 1 and 3).
    @Test func adjacentRendering_countMatchesPosition() throws {
        let container = try makeContainer()
        let pages = try makePages(in: container.mainContext, count: 4)
        let harness = makeHarness(pages: pages)

        harness.coordinator.rebuildPages(pages: pages, toolbar: ToolbarState(), viewport: nil)

        // On page 0: live(0) + adjacent(1) = 2.
        #expect(harness.coordinator.canvasPageIndex == 0)
        #expect(canvasCount(in: harness.containerView) == 2)

        // Jump to page 2: live(2) + adjacent(1, 3) = 3.
        let targetFrame = harness.coordinator.pageFrames[2]
        harness.scrollView.contentOffset = CGPoint(x: 0, y: targetFrame.midY - harness.scrollView.bounds.height / 2)
        harness.coordinator.scrollViewDidEndDecelerating(harness.scrollView)

        #expect(harness.coordinator.canvasPageIndex == 2)
        #expect(canvasCount(in: harness.containerView) == 3)
    }

    // On last page of 4: live(3) + adjacent(2) = 2.
    @Test func adjacentRendering_lastPage_hasTwoCanvases() throws {
        let container = try makeContainer()
        let pages = try makePages(in: container.mainContext, count: 4)
        let harness = makeHarness(pages: pages)

        harness.coordinator.rebuildPages(pages: pages, toolbar: ToolbarState(), viewport: nil)

        let targetFrame = harness.coordinator.pageFrames[3]
        harness.scrollView.contentOffset = CGPoint(x: 0, y: targetFrame.midY - harness.scrollView.bounds.height / 2)
        harness.coordinator.scrollViewDidEndDecelerating(harness.scrollView)

        #expect(harness.coordinator.canvasPageIndex == 3)
        #expect(canvasCount(in: harness.containerView) == 2)
    }
}
