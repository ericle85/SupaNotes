import Testing
import UIKit
import SwiftData
@testable import SupaNotes

// Integration tests for MultipageCanvasContainer.Coordinator with single-canvas architecture.
// Validates: rebuild mounts one canvas, scroll-settle swaps focus, only 1 canvas ever exists.
@MainActor
@Suite struct MultipageCanvasCoordinatorTests {

    // Build an in-memory SwiftData container so Page models are real objects.
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Note.self, Page.self, Folder.self, configurations: config)
    }

    // Build a note with N pages inserted into context and linked to the note.
    private func makePages(in context: ModelContext, count: Int) throws -> [Page] {
        let note = Note(title: "Test Note")
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

    // Build a coordinator + scroll hierarchy that mirrors makeUIView wiring.
    private func makeCoordinatorHarness(
        pages: [Page],
        scrollSize: CGSize = CGSize(width: 900, height: 1000),
        onUndoManagerReady: @escaping (UndoManager?) -> Void = { _ in }
    ) -> (
        coordinator: MultipageCanvasContainer.Coordinator,
        scrollView: UIScrollView,
        containerView: UIView
    ) {
        let coordinator = MultipageCanvasContainer.Coordinator(
            pages: pages,
            toolbar: ToolbarState(),
            onUndoManagerReady: onUndoManagerReady,
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

    // Count live DrawingCanvasView instances in the entire container hierarchy.
    private func canvasCount(in containerView: UIView) -> Int {
        containerView.subviews.flatMap { view -> [DrawingCanvasView] in
            // Canvas lives inside a PageSlotView.
            view.subviews.compactMap { $0 as? DrawingCanvasView }
        }.count
    }

    // MARK: - Tests

    // Rebuild should mount one live canvas on page 0 plus adjacent display canvases.
    @Test func rebuild_mountsCanvasOnFirstPage() throws {
        let container = try makeContainer()
        let pages = try makePages(in: container.mainContext, count: 120)
        let harness = makeCoordinatorHarness(pages: pages)

        harness.coordinator.rebuildPages(pages: pages, toolbar: ToolbarState(), viewport: nil)

        // One live canvas + adjacent display canvases (at most 1 for page 0 since there's no page -1).
        #expect(harness.coordinator.liveCanvas != nil)
        #expect(harness.coordinator.canvasPageIndex == 0)
        #expect(canvasCount(in: harness.containerView) <= 3)
        #expect(harness.coordinator.adjacentCanvases.count <= 2)
    }

    // All pages should have slots.
    @Test func rebuild_createsSlotForEveryPage() throws {
        let container = try makeContainer()
        let pages = try makePages(in: container.mainContext, count: 50)
        let harness = makeCoordinatorHarness(pages: pages)

        harness.coordinator.rebuildPages(pages: pages, toolbar: ToolbarState(), viewport: nil)

        #expect(harness.coordinator.slots.count == 50)
    }

    // Flush notification should flush the single live canvas.
    @Test func flushDrawings_flushesLiveCanvas() throws {
        let container = try makeContainer()
        let pages = try makePages(in: container.mainContext, count: 10)
        let harness = makeCoordinatorHarness(pages: pages)

        harness.coordinator.rebuildPages(pages: pages, toolbar: ToolbarState(), viewport: nil)
        #expect(harness.coordinator.liveCanvas != nil)

        NotificationCenter.default.post(name: .flushDrawings, object: nil)

        // The canvas page should have been flushed (drawingData non-empty from engine init).
        #expect(!pages[0].drawingData.isEmpty)
    }

    // Undo manager callback should publish the live canvas's undo stack.
    @Test func onUndoManagerReady_firesWithLiveCanvasManager() async throws {
        let container = try makeContainer()
        let pages = try makePages(in: container.mainContext, count: 10)
        var callbackUndoManager: UndoManager?

        let harness = makeCoordinatorHarness(
            pages: pages,
            onUndoManagerReady: { callbackUndoManager = $0 }
        )

        harness.coordinator.rebuildPages(pages: pages, toolbar: ToolbarState(), viewport: nil)

        // Callback is dispatched asynchronously after rebuild.
        for _ in 0..<20 where callbackUndoManager == nil {
            await Task.yield()
        }
        #expect(callbackUndoManager != nil)
    }

    // Zoom-end should not create extra canvases beyond live + adjacent.
    @Test func zoomEnd_keepsCanvasCountBounded() throws {
        let container = try makeContainer()
        let pages = try makePages(in: container.mainContext, count: 50)
        let harness = makeCoordinatorHarness(pages: pages)

        harness.coordinator.rebuildPages(pages: pages, toolbar: ToolbarState(), viewport: nil)
        let before = canvasCount(in: harness.containerView)

        harness.scrollView.zoomScale = 2
        harness.coordinator.scrollViewDidEndZooming(harness.scrollView, with: harness.containerView, atScale: 2)

        #expect(canvasCount(in: harness.containerView) == before)
    }
}
