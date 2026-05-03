import Testing
import SwiftData
import Foundation
@testable import SupaNotes

@MainActor
@Suite struct PDFImportTests {
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

        PDFImporter.importPDF(data: originalData, into: note, modelContext: context)

        #expect(note.sortedPages.count > 0)
        #expect(note.sortedPages.allSatisfy { $0.drawingData.isEmpty })

        let exportedData = try #require(PDFExporter.exportNote(note, pages: nil), "Export returned nil")

        #expect(exportedData.count <= originalData.count)
    }
}
