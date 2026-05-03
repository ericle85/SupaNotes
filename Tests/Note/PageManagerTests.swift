import Testing
import Foundation
import SwiftData
@testable import SupaNotes

/// Tests for PageManager — pure data contract for adding pages to a Note.
@MainActor
@Suite struct PageManagerTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Note.self, Page.self, Folder.self, configurations: config)
    }

    /// Create a note whose pages are all inserted in the context.
    private func makeNote(in context: ModelContext, pageCount: Int = 1) throws -> Note {
        let note = Note(title: "T")
        context.insert(note)
        for i in 0..<pageCount {
            let page = Page(orderIndex: i)
            context.insert(page)
            page.note = note
        }
        try context.save()
        return note
    }

    // MARK: - addPage (default = .end)

    @Test func addPage_appendsPageWithNextOrderIndex() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let note = try makeNote(in: context, pageCount: 1)
        let manager = PageManager(modelContext: context)

        manager.addPage(to: note)

        #expect(note.pages.count == 2)
        #expect(note.sortedPages.last?.orderIndex == 1)
    }

    @Test func addPage_multipleCalls_produceContiguousIndices() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let note = try makeNote(in: context, pageCount: 1)
        let manager = PageManager(modelContext: context)

        manager.addPage(to: note)
        manager.addPage(to: note)
        manager.addPage(to: note)

        let indices = note.sortedPages.map(\.orderIndex)
        #expect(indices == [0, 1, 2, 3])
    }

    @Test func addPage_updatesNoteUpdatedAt() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let note = try makeNote(in: context, pageCount: 1)
        let manager = PageManager(modelContext: context)
        let before = Date.distantPast
        note.updatedAt = before

        manager.addPage(to: note)

        #expect(note.updatedAt > before)
    }

    @Test func addPage_linksPageToNote() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let note = try makeNote(in: context, pageCount: 1)
        let manager = PageManager(modelContext: context)

        manager.addPage(to: note)

        let added = note.sortedPages.last
        #expect(added?.note === note)
    }

    @Test func addPage_toEmptyNote_createsFirstPage() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let note = try makeNote(in: context, pageCount: 0)
        let manager = PageManager(modelContext: context)

        manager.addPage(to: note)

        #expect(note.pages.count == 1)
        #expect(note.sortedPages.first?.orderIndex == 0)
    }

    // MARK: - addPage at .above

    @Test func addPage_above_shiftsExistingIndices() throws {
        let container = try makeContainer()
        let context = container.mainContext
        // Pages at indices 0, 1.
        let note = try makeNote(in: context, pageCount: 2)
        let manager = PageManager(modelContext: context)

        // Insert above page at orderIndex 1 — it should become index 1, old page 1 becomes 2.
        manager.addPage(to: note, at: .above(1))

        let indices = note.sortedPages.map(\.orderIndex)
        #expect(indices == [0, 1, 2])
        #expect(note.pages.count == 3)
    }

    @Test func addPage_above_firstPage_insertsAtZero() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let note = try makeNote(in: context, pageCount: 2)
        let manager = PageManager(modelContext: context)

        manager.addPage(to: note, at: .above(0))

        let indices = note.sortedPages.map(\.orderIndex)
        #expect(indices == [0, 1, 2])
        // The new page is at index 0.
        #expect(note.sortedPages.first?.drawingData.isEmpty == true)
    }

    // MARK: - addPage at .below

    @Test func addPage_below_insertsAfterTarget() throws {
        let container = try makeContainer()
        let context = container.mainContext
        // Pages at indices 0, 1, 2.
        let note = try makeNote(in: context, pageCount: 3)
        let manager = PageManager(modelContext: context)

        // Insert below page at orderIndex 1 — new page at 2, old page 2 becomes 3.
        manager.addPage(to: note, at: .below(1))

        let indices = note.sortedPages.map(\.orderIndex)
        #expect(indices == [0, 1, 2, 3])
        #expect(note.pages.count == 4)
    }

    @Test func addPage_below_lastPage_appendsToEnd() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let note = try makeNote(in: context, pageCount: 2)
        let manager = PageManager(modelContext: context)

        // Insert below the last page (orderIndex 1).
        manager.addPage(to: note, at: .below(1))

        let indices = note.sortedPages.map(\.orderIndex)
        #expect(indices == [0, 1, 2])
        #expect(note.sortedPages.last?.drawingData.isEmpty == true)
    }

    @Test func addPage_above_firstPage_pushesAllDown() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let note = try makeNote(in: context, pageCount: 3)
        let manager = PageManager(modelContext: context)

        // Insert above the first page (orderIndex 0).
        manager.addPage(to: note, at: .above(0))

        let indices = note.sortedPages.map(\.orderIndex)
        #expect(indices == [0, 1, 2, 3])
        #expect(note.pages.count == 4)
    }
}
