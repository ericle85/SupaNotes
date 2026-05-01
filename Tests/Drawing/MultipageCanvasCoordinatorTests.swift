import Testing
import UIKit
import SwiftData
@testable import SupaNotes

// Integration tests for MultipageCanvasContainer.Coordinator + PageRecycler.
// These tests focus on recycler-window behavior instead of per-canvas logic.
@MainActor
@Suite struct MultipageCanvasCoordinatorTests {

    // Build an in-memory SwiftData container so Page models are real objects.
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Note.self, Page.self, Folder.self, configurations: config)
    }

    // Build a note with N pages inserted into context and linked to the note.
    private func makePages(in context: ModelContext, count: Int) throws -> [Page] {
        let note = Note(title: "Recycler Note")
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

    // Active canvas indices currently mounted in the container.
    private func activeIndices(in containerView: UIView) -> Set<Int> {
        Set(containerView.subviews.compactMap { ($0 as? DrawingCanvasView)?.tag })
    }


    // MARK: - Coordinator + recycler integration

    // Rebuild should configure a bounded active window instead of mounting every page.
    @Test func rebuild_configuresRecyclerAndActivatesBoundedWindow() throws {
        let container = try makeContainer()
        let pages = try makePages(in: container.mainContext, count: 120)
        let harness = makeCoordinatorHarness(pages: pages)

        harness.coordinator.rebuildPages(pages: pages, toolbar: ToolbarState(), viewport: nil)

        let active = activeIndices(in: harness.containerView)
        #expect(!active.isEmpty)
        #expect(active.count < pages.count)
        #expect(active.contains(0))
    }

    // Scrolling far down should rotate the active recycler window.
    @Test func scroll_updatesActiveWindow() throws {
        let container = try makeContainer()
        let pages = try makePages(in: container.mainContext, count: 120)
        let harness = makeCoordinatorHarness(pages: pages)

        harness.coordinator.rebuildPages(pages: pages, toolbar: ToolbarState(), viewport: nil)
        let firstActive = activeIndices(in: harness.containerView)
        #expect(firstActive.contains(0))

        // Move far enough to leave the first pages behind.
        harness.scrollView.contentOffset = CGPoint(x: 0, y: 20_000)
        harness.coordinator.scrollViewDidScroll(harness.scrollView)

        let secondActive = activeIndices(in: harness.containerView)
        #expect(!secondActive.isEmpty)
        #expect(!secondActive.contains(0))
        #expect(firstActive != secondActive)
    }

    // Flush notification should only flush currently active canvases.
    @Test func flushDrawings_flushesOnlyActiveCanvases() throws {
        let container = try makeContainer()
        let pages = try makePages(in: container.mainContext, count: 80)
        let harness = makeCoordinatorHarness(pages: pages)

        harness.coordinator.rebuildPages(pages: pages, toolbar: ToolbarState(), viewport: nil)
        let active = activeIndices(in: harness.containerView)
        #expect(!active.isEmpty)
        #expect(active.count < pages.count)

        NotificationCenter.default.post(name: .flushDrawings, object: nil)

        for (index, page) in pages.enumerated() {
            if active.contains(index) {
                #expect(!page.drawingData.isEmpty)
            } else {
                #expect(page.drawingData.isEmpty)
            }
        }
    }

    // Undo manager callback should still publish the active page's undo stack.
    @Test func onUndoManagerReady_firesWithActivePageManager() async throws {
        let container = try makeContainer()
        let pages = try makePages(in: container.mainContext, count: 40)
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

    // Switching notes must replace canvases for the new note's pages, not keep
    // the previous note's canvases mounted. Mimics the tab-switch flow where
    // SwiftUI re-uses the same Coordinator and pushes new pages via the
    // `pages` setter rather than going through makeCoordinator + makeUIView.
    @Test func switchNote_samePageCount_rendersNewNoteImmediately() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Two notes with the same page count but distinct Page identities.
        let pagesA = try makePages(in: context, count: 3)
        let pagesB = try makePages(in: context, count: 3)
        #expect(pagesA.map(\.persistentModelID) != pagesB.map(\.persistentModelID))

        let harness = makeCoordinatorHarness(pages: pagesA)
        harness.coordinator.rebuildPages(pages: pagesA, toolbar: ToolbarState(), viewport: nil)

        let pageIDsA = Set(pagesA.map(\.persistentModelID))
        let mountedAfterA = harness.coordinator.recycler.activeViews.values
            .map { $0.page.persistentModelID }
        #expect(Set(mountedAfterA).isSubset(of: pageIDsA))
        #expect(!mountedAfterA.isEmpty)

        // Simulate the SwiftUI binding update that fires on tab switch.
        harness.coordinator.pages = pagesB

        let pageIDsB = Set(pagesB.map(\.persistentModelID))
        let mountedAfterB = harness.coordinator.recycler.activeViews.values
            .map { $0.page.persistentModelID }
        #expect(!mountedAfterB.isEmpty, "Expected new note's canvases to be mounted after pages switch")
        #expect(Set(mountedAfterB).isSubset(of: pageIDsB), "Mounted canvases must belong to the new note")
        #expect(Set(mountedAfterB).isDisjoint(with: pageIDsA), "No canvases from previous note should remain")
    }

    // Zoom-end updates should only target active canvases (window stays bounded).
    @Test func zoomEnd_keepsActiveWindowBounded() throws {
        let container = try makeContainer()
        let pages = try makePages(in: container.mainContext, count: 140)
        let harness = makeCoordinatorHarness(pages: pages)

        harness.coordinator.rebuildPages(pages: pages, toolbar: ToolbarState(), viewport: nil)
        let before = activeIndices(in: harness.containerView)
        #expect(!before.isEmpty)

        harness.scrollView.zoomScale = 2
        harness.coordinator.scrollViewDidEndZooming(harness.scrollView, with: harness.containerView, atScale: 2)

        let after = activeIndices(in: harness.containerView)
        #expect(after == before)
        #expect(after.count < pages.count)
    }

}
