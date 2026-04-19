import Testing
import SwiftData
import Foundation
import UIKit
@testable import SupaNotes

@MainActor
struct PDFImportTests {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Note.self, Page.self, Folder.self, configurations: config)
    }

    @Test func importPDF_storesOriginalDataAndCreatesPlaceholders() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let note = Note(title: "Import Test")
        context.insert(note)
        
        // 1. Create a minimal valid PDF (1 page)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 100))
        let actualPdfData = renderer.pdfData { ctx in
            ctx.beginPage()
            "Test Page".draw(at: CGPoint(x: 10, y: 10), withAttributes: nil)
        }
        
        // 2. Action: Import the PDF data
        PDFService.importPDF(data: actualPdfData, into: note, modelContext: context)
        
        // 3. Verify: The note should store the original PDF data
        #expect(note.originalPdfData == actualPdfData)
        
        // 4. Verify: Pages should reference the PDF instead of containing bitmaps
        let pages = note.sortedPages
        #expect(pages.count == 1) 
        #expect(pages.first?.backgroundImageData == nil) 
        #expect(pages.first?.pdfPageNumber == 0)
    }
}
