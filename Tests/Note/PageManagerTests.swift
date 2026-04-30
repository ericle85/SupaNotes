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
    /// Mirrors the pattern from NoteModelTests.sortedPages test.
    private func makeNote(in context: ModelContext, pageCount: Int = 1) throws -> Note {
        let note = Note(title: "T")
        context.insert(note)
        note.pages = []
        for i in 0..<pageCount {
            let page = Page(orderIndex: i)
            context.insert(page)
            page.note = note
        }
        try context.save()
        return note
    }

    // MARK: - addPage

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

    // MARK: - addPageAbove

    @Test func addPageAbove_shiftsExistingIndices() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let note = try makeNote(in: context, pageCount: 2)
        let manager = PageManager(modelContext: context)

        manager.addPageAbove(in: note)

        let indices = note.sortedPages.map(\.orderIndex)
        #expect(indices == [0, 1, 2])
        #expect(note.pages.count == 3)
    }

    @Test func addPageAbove_onEmptyPages_insertsAtZero() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let note = try makeNote(in: context, pageCount: 0)
        let manager = PageManager(modelContext: context)

        manager.addPageAbove(in: note)

        #expect(note.pages.count == 1)
        #expect(note.sortedPages.first?.orderIndex == 0)
    }
}
