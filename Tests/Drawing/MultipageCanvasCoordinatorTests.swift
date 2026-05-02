@testable import SupaNotes
import SwiftData
import Testing
import UIKit

// Integration tests for MultipageCanvasContainer.Coordinator with single-canvas architecture.
// Validates: rebuild mounts one canvas, scroll-settle swaps focus, only 1 canvas ever exists.
@MainActor
struct MultipageCanvasCoordinatorTests {
    /// Scroll spy that lets tests simulate whether the scroll view is currently moving.
    private final class MotionStateScrollView: UIScrollView {
        /// Test-controlled deceleration flag so coordinator can branch deterministically.
        var deceleratingOverride = false

        /// Expose test-controlled value instead of UIKit runtime state.
        override var isDecelerating: Bool {
            deceleratingOverride
        }
    }

    /// Build an in-memory SwiftData container so Page models are real objects.
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Note.self, Page.self, Folder.self, configurations: config)
    }

    /// Build a note with N pages inserted into context and linked to the note.
    private func makePages(in context: ModelContext, count: Int) throws -> [Page] {
        let note = Note(title: "Test Note")
        context.insert(note)
        note.pages = []
        for i in 0 ..< count {
            let page = Page(orderIndex: i)
            context.insert(page)
            page.note = note
        }
        try context.save()
        return note.sortedPages
    }

    /// Build a coordinator + scroll hierarchy that mirrors makeUIView wiring.
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

    /// Count live DrawingCanvasView instances in the entire container hierarchy.
    private func canvasCount(in containerView: UIView) -> Int {
        containerView.subviews.flatMap { view -> [DrawingCanvasView] in
            // Canvas lives inside a PageSlotView.
            view.subviews.compactMap { $0 as? DrawingCanvasView }
        }.count
    }

    // MARK: - Tests

    /// When pencil drawing begins during momentum scrolling, coordinator should request a
    /// momentum stop immediately so the page does not keep gliding under the Pencil.
    @Test func pencilBegin_whileScrollMoving_pinsContentOffsetToStopMomentum() throws {
        let container = try makeContainer()
        let pages = try makePages(in: container.mainContext, count: 1)

        // Build coordinator with a real scroll view and a callback seam to verify intent.
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
        let scrollView = MotionStateScrollView(frame: CGRect(x: 0, y: 0, width: 900, height: 1000))
        // Simulate that momentum is currently active when Pencil touches down.
        scrollView.deceleratingOverride = true
        coordinator.scrollView = scrollView
        var stopRequestCount = 0
        coordinator.onRequestStopScrollMomentum = { _ in
            // Count every explicit request to stop in-flight motion.
            stopRequestCount += 1
        }

        // Any real canvas instance is fine here; we only need to trigger the delegate callback path.
        let canvas = DrawingCanvasView(
            page: pages[0],
            frame: .zero,
            toolStyle: ToolStyle.from(toolbar: ToolbarState()),
            onPageMutated: {}
        )
        let shouldDrawThisTouch = coordinator.pageCanvasViewDidBeginUsingTool(canvas)

        // Pencil-down during momentum should stop scrolling AND begin drawing.
        #expect(shouldDrawThisTouch)
        // Scrolling disabled while drawing is active.
        #expect(!scrollView.isScrollEnabled)
        // We still expect an explicit momentum-stop request for this first Pencil contact.
        #expect(stopRequestCount == 1)
    }

    /// Rebuild should mount one live canvas on page 0 plus adjacent display canvases.
    @Test func rebuild_mountsCanvasOnFirstPage() throws {
        let container = try makeContainer()
        let pages = try makePages(in: container.mainContext, count: 120)
        let harness = makeCoordinatorHarness(pages: pages)

        harness.coordinator.rebuildPages(pages: pages, toolbar: ToolbarState(), viewport: nil)

        // One live canvas + adjacent display canvases (at most 1 for page 0 since there's no page -1).
        #expect(!harness.coordinator.liveCanvases.isEmpty)
        #expect(harness.coordinator.liveCanvases[0] != nil)
        #expect(canvasCount(in: harness.containerView) <= 3)
        #expect(harness.coordinator.adjacentCanvases.count <= 2)
    }

    /// All pages should have slots.
    @Test func rebuild_createsSlotForEveryPage() throws {
        let container = try makeContainer()
        let pages = try makePages(in: container.mainContext, count: 50)
        let harness = makeCoordinatorHarness(pages: pages)

        harness.coordinator.rebuildPages(pages: pages, toolbar: ToolbarState(), viewport: nil)

        #expect(harness.coordinator.slots.count == 50)
    }

    /// Flush notification should flush the single live canvas.
    @Test func flushDrawings_flushesLiveCanvas() throws {
        let container = try makeContainer()
        let pages = try makePages(in: container.mainContext, count: 10)
        let harness = makeCoordinatorHarness(pages: pages)

        harness.coordinator.rebuildPages(pages: pages, toolbar: ToolbarState(), viewport: nil)
        #expect(!harness.coordinator.liveCanvases.isEmpty)

        NotificationCenter.default.post(name: .flushDrawings, object: nil)

        // The canvas page should have been flushed (drawingData non-empty from engine init).
        #expect(!pages[0].drawingData.isEmpty)
    }

    /// Undo manager callback should publish the live canvas's undo stack.
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
        for _ in 0 ..< 20 where callbackUndoManager == nil {
            await Task.yield()
        }
        #expect(callbackUndoManager != nil)
    }

    /// Zoom-end should not create extra canvases beyond live + adjacent.
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
