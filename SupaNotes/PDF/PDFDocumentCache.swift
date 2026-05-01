import Foundation
import PDFKit

// Caches a single PDFDocument per Note so we don't re-parse the same
// raw Data on every bitmap render, canvas mount, and adjacent mount.
// Thread-safe via @MainActor since all callers run on the main thread.
@MainActor
enum PDFDocumentCache {
    // One cached document — only one note is open at a time.
    private static var cachedNoteID: UUID?
    private static var cachedDocument: PDFDocument?

    // Return the cached PDFDocument for a note, parsing only on first access.
    static func document(for note: Note) -> PDFDocument? {
        if note.id == cachedNoteID, let doc = cachedDocument { return doc }
        guard let data = note.originalPdfData else { return nil }
        let doc = PDFDocument(data: data)
        cachedNoteID = note.id
        cachedDocument = doc
        return doc
    }

    // Call when closing a note to free memory.
    static func evict() {
        cachedNoteID = nil
        cachedDocument = nil
    }
}
