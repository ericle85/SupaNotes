import Testing
import UIKit
import SwiftData
@testable import SupaNotes

// Tests for the multi-canvas visible-page architecture. Validates that the coordinator
// mounts live canvases on all visible pages and adjacent display canvases ±1 from visible range.
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

    // Simulate real scroll flow: set offset → scrollViewDidScroll → settle.
    private func simulateScroll(
        to offset: CGPoint,
        coordinator: MultipageCanvasContainer.Coordinator,
        scrollView: UIScrollView
    ) {
        scrollView.contentOffset = offset
        coordinator.scrollViewDidScroll(scrollView)
        coordinator.scrollViewDidEndDecelerating(scrollView)
    }

    // MARK: - Tests

    // After rebuild, live canvas on visible pages + adjacent display canvases.
    @Test func rebuild_mountsCanvasOnVisiblePages() throws {
        let container = try makeContainer()
        let pages = try makePages(in: container.mainContext, count: 5)
        let harness = makeHarness(pages: pages)

        harness.coordinator.rebuildPages(pages: pages, toolbar: ToolbarState(), viewport: nil)

        // Page 0 should have a live canvas.
        #expect(harness.coordinator.liveCanvases[0] != nil)
        #expect(!harness.coordinator.liveCanvases.isEmpty)
        // At least 1 live + adjacent canvases present.
        #expect(canvasCount(in: harness.containerView) >= 2)
    }

    // Scroll-settle to a different page reconciles canvases.
    @Test func scrollSettle_reconcilesCanvases() throws {
        let container = try makeContainer()
        let pages = try makePages(in: container.mainContext, count: 20)
        let harness = makeHarness(pages: pages)

        harness.coordinator.rebuildPages(pages: pages, toolbar: ToolbarState(), viewport: nil)
        #expect(harness.coordinator.liveCanvases[0] != nil)

        // Scroll far enough that page 0 is no longer visible.
        let targetFrame = harness.coordinator.pageFrames[10]
        simulateScroll(
            to: CGPoint(x: 0, y: targetFrame.midY - harness.scrollView.bounds.height / 2),
            coordinator: harness.coordinator, scrollView: harness.scrollView
        )

        // Page 0 should no longer have a live canvas; page 10 should.
        #expect(harness.coordinator.liveCanvases[0] == nil)
        #expect(harness.coordinator.liveCanvases[10] != nil)
    }

// Live canvas slots should NOT have bitmaps (canvas covers them).
    @Test func canvasSlot_hasNoBitmap() throws {
        let container = try makeContainer()
        let pages = try makePages(in: container.mainContext, count: 5)
        let harness = makeHarness(pages: pages)

        harness.coordinator.rebuildPages(pages: pages, toolbar: ToolbarState(), viewport: nil)

        // Every live canvas slot should have nil bitmap.
        for index in harness.coordinator.liveCanvases.keys {
            #expect(harness.coordinator.slots[index].bitmap == nil)
        }
    }

    // Single-page note: canvas stays on page 0.
    @Test func singlePage_canvasStaysOnPage0() throws {
        let container = try makeContainer()
        let pages = try makePages(in: container.mainContext, count: 1)
        let harness = makeHarness(pages: pages)

        harness.coordinator.rebuildPages(pages: pages, toolbar: ToolbarState(), viewport: nil)
        harness.coordinator.scrollViewDidEndDecelerating(harness.scrollView)

        #expect(harness.coordinator.liveCanvases[0] != nil)
        #expect(canvasCount(in: harness.containerView) == 1)
    }

    // Settling on same position should not recreate canvases.
    @Test func settleOnSamePosition_noChange() throws {
        let container = try makeContainer()
        let pages = try makePages(in: container.mainContext, count: 5)
        let harness = makeHarness(pages: pages)

        harness.coordinator.rebuildPages(pages: pages, toolbar: ToolbarState(), viewport: nil)
        let firstCanvas = harness.coordinator.liveCanvases[0]

        // Scroll within page 0 and settle.
        harness.scrollView.contentOffset = CGPoint(x: 0, y: 10)
        harness.coordinator.scrollViewDidEndDecelerating(harness.scrollView)

        // Same canvas instance — no swap occurred.
        #expect(harness.coordinator.liveCanvases[0] === firstCanvas)
    }

    // MARK: - Adjacent rendering

    // Adjacent canvases should be ±1 from the visible range edges.
    @Test func adjacentRendering_surroundsVisibleRange() throws {
        let container = try makeContainer()
        let pages = try makePages(in: container.mainContext, count: 20)
        let harness = makeHarness(pages: pages)

        harness.coordinator.rebuildPages(pages: pages, toolbar: ToolbarState(), viewport: nil)

        // Jump to a middle page so both ±1 adjacents exist.
        let targetFrame = harness.coordinator.pageFrames[10]
        simulateScroll(
            to: CGPoint(x: 0, y: targetFrame.midY - harness.scrollView.bounds.height / 2),
            coordinator: harness.coordinator, scrollView: harness.scrollView
        )

        let liveKeys = Set(harness.coordinator.liveCanvases.keys)
        let adjKeys = Set(harness.coordinator.adjacentCanvases.keys)

        // Adjacent canvases should not overlap with live canvases.
        #expect(liveKeys.isDisjoint(with: adjKeys))
        // Adjacent count should be at most 2 (one below, one above visible range).
        #expect(adjKeys.count <= 2)
    }

    // On last page: adjacent canvas only on the page before.
    @Test func adjacentRendering_lastPage() throws {
        let container = try makeContainer()
        let pages = try makePages(in: container.mainContext, count: 4)
        let harness = makeHarness(pages: pages)

        harness.coordinator.rebuildPages(pages: pages, toolbar: ToolbarState(), viewport: nil)

        let targetFrame = harness.coordinator.pageFrames[3]
        simulateScroll(
            to: CGPoint(x: 0, y: targetFrame.midY - harness.scrollView.bounds.height / 2),
            coordinator: harness.coordinator, scrollView: harness.scrollView
        )

        #expect(harness.coordinator.liveCanvases[3] != nil)
        // No adjacent canvas beyond the last page.
        #expect(harness.coordinator.adjacentCanvases[4] == nil)
    }
}
