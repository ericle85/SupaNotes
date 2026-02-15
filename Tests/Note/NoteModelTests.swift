import Testing
import SwiftData
@testable import SupaNotes

@MainActor
struct NoteModelTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Note.self, Page.self, Folder.self, configurations: config)
    }

    // MARK: - moveToTrash

    @Test func moveToTrash_setsIsDeletedAndDeletedAt() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let note = Note(title: "Test")
        context.insert(note)

        note.moveToTrash()

        #expect(note.isDeleted == true)
        #expect(note.deletedAt != nil)
    }

    // MARK: - restore

    @Test func restore_clearsIsDeletedAndDeletedAt() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let note = Note(title: "Test")
        context.insert(note)
        note.moveToTrash()

        note.restore()

        #expect(note.isDeleted == false)
        #expect(note.deletedAt == nil)
    }

    @Test func restore_afterMoveToTrash_roundTrips() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let note = Note(title: "Test")
        context.insert(note)

        note.moveToTrash()
        #expect(note.isDeleted == true)

        note.restore()
        #expect(note.isDeleted == false)
        #expect(note.deletedAt == nil)
    }

    // MARK: - sortedPages

    @Test func sortedPages_returnsPagesSortedByOrderIndex() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let note = Note(title: "Test")
        context.insert(note)

        // Clear default page and add pages in reverse order
        note.pages = []
        let page3 = Page(orderIndex: 2)
        let page1 = Page(orderIndex: 0)
        let page2 = Page(orderIndex: 1)
        note.pages = [page3, page1, page2]
        try context.save()

        let sorted = note.sortedPages
        #expect(sorted.count == 3)
        #expect(sorted[0].orderIndex == 0)
        #expect(sorted[1].orderIndex == 1)
        #expect(sorted[2].orderIndex == 2)
    }

    // MARK: - init defaults

    @Test func init_setsDefaultValues() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let note = Note()
        context.insert(note)

        #expect(note.title == "Untitled Note")
        #expect(note.isDeleted == false)
        #expect(note.deletedAt == nil)
        #expect(note.pages.count == 1)
    }
}
