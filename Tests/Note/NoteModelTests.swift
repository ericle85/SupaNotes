import Testing
import SwiftData
@testable import SupaNotes

/// Tests for the Note model
/// A Note contains multiple Pages and can be moved to trash or restored
/// SwiftData is the framework we use to save notes to the database
@MainActor
struct NoteModelTests {

    /// Helper function that creates an in-memory database for testing
    /// (so we don't have to save to the real database during tests)
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Note.self, Page.self, Folder.self, configurations: config)
    }

    // MARK: - moveToTrash
    // Tests for marking a note as deleted

    @Test func moveToTrash_setsIsDeletedAndDeletedAt() throws {
        // Set up: create a test database and a note
        let container = try makeContainer()
        let context = container.mainContext
        let note = Note(title: "Test")
        context.insert(note)  // Add to the test database

        // Action: move the note to trash
        note.moveToTrash()

        // Verify: the note should be marked as deleted with a timestamp
        #expect(note.isDeleted == true)      // Marked as deleted
        #expect(note.deletedAt != nil)       // Has a deletion timestamp
    }

    // MARK: - restore
    // Tests for undeleting a note that was in trash

    @Test func restore_clearsIsDeletedAndDeletedAt() throws {
        // Set up: create a note and move it to trash
        let container = try makeContainer()
        let context = container.mainContext
        let note = Note(title: "Test")
        context.insert(note)
        note.moveToTrash()  // Now it's deleted

        // Action: restore the note
        note.restore()

        // Verify: it should no longer be marked as deleted
        #expect(note.isDeleted == false)    // No longer deleted
        #expect(note.deletedAt == nil)      // No deletion timestamp
    }

    @Test func restore_afterMoveToTrash_roundTrips() throws {
        // This test verifies that delete -> restore brings the note back to its original state
        let container = try makeContainer()
        let context = container.mainContext
        let note = Note(title: "Test")
        context.insert(note)

        // Move to trash
        note.moveToTrash()
        #expect(note.isDeleted == true)

        // Restore from trash
        note.restore()
        // Should be back to normal
        #expect(note.isDeleted == false)
        #expect(note.deletedAt == nil)
    }

    // MARK: - sortedPages
    // Tests for getting pages in the correct order

    @Test func sortedPages_returnsPagesSortedByOrderIndex() throws {
        // Set up: create a note with pages in random order
        let container = try makeContainer()
        let context = container.mainContext
        let note = Note(title: "Test")
        context.insert(note)

        // Clear the default page and add pages in reverse order
        note.pages = []
        let page3 = Page(orderIndex: 2)  // This should be page 3
        let page1 = Page(orderIndex: 0)  // This should be page 1
        let page2 = Page(orderIndex: 1)  // This should be page 2
        note.pages = [page3, page1, page2]  // Add them in wrong order
        try context.save()

        // Get the sorted pages
        let sorted = note.sortedPages

        // Verify: pages should be sorted by orderIndex despite being added wrong
        #expect(sorted.count == 3)                  // All 3 pages are there
        #expect(sorted[0].orderIndex == 0)          // First page has index 0
        #expect(sorted[1].orderIndex == 1)          // Second page has index 1
        #expect(sorted[2].orderIndex == 2)          // Third page has index 2
    }

    // MARK: - init defaults
    // Tests for default values when creating a new note

    @Test func init_setsDefaultValues() throws {
        // Create a new note without specifying any values
        let container = try makeContainer()
        let context = container.mainContext
        let note = Note()
        context.insert(note)

        // Verify: default values are set correctly
        #expect(note.title == "Untitled Note")     // Default title
        #expect(note.isDeleted == false)           // New notes are not deleted
        #expect(note.deletedAt == nil)             // No deletion timestamp
        #expect(note.pages.count == 1)             // New notes start with 1 blank page
    }
}
