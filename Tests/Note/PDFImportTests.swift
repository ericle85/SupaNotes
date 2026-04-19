import Testing
import SwiftData
import Foundation
@testable import SupaNotes

@MainActor
struct PDFImportTests {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Note.self, Page.self, Folder.self, configurations: config)
    }

    private func fixtureURL(_ filename: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent(filename)
    }

    @Test func exportImportedPDF_withoutAnnotations_isSameSizeOrSmaller() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let note = Note(title: "PDF Import Roundtrip")
        context.insert(note)

        let originalURL = fixtureURL("482kb.pdf")
        let originalData = try Data(contentsOf: originalURL)

        PDFService.importPDF(data: originalData, into: note, modelContext: context)

        #expect(note.sortedPages.count > 0)
        #expect(note.sortedPages.allSatisfy { $0.drawingData.isEmpty })

        guard let exportedData = PDFService.exportNote(note, pages: nil) else {
            Issue.record("Export failed")
            return
        }

        print("Original PDF size: \(originalData.count) bytes")
        print("Exported PDF size: \(exportedData.count) bytes")

        #expect(exportedData.count <= originalData.count)
    }
}
