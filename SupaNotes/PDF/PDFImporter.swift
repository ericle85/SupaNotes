import Foundation
import PDFKit
import SwiftData
import UIKit

// Imports PDF files and images into a Note by creating Page models.
// All page creation is routed through PageManager.insertPage.
enum PDFImporter {

    // MARK: - PDF Import

    // Imports a PDF from a file URL, creating one Page per PDF page.
    static func importPDF(url: URL, into note: Note, modelContext: ModelContext) {
        guard let data = try? Data(contentsOf: url) else { return }
        importPDF(data: data, into: note, modelContext: modelContext)
    }

    // Imports a PDF from raw data, creating one Page per PDF page.
    static func importPDF(data: Data, into note: Note, modelContext: ModelContext) {
        guard let doc = PDFDocument(data: data) else { return }

        // Store the original PDF data once on the note.
        note.originalPdfData = data

        let pageManager = PageManager(modelContext: modelContext)
        for i in 0 ..< doc.pageCount {
            pageManager.insertPage(into: note) { page in
                page.pdfPageNumber = i
                // Store the PDF page's native dimensions so the canvas matches.
                if let pdfPage = doc.page(at: i) {
                    let mediaBox = pdfPage.bounds(for: .mediaBox)
                    page.customWidth = Double(mediaBox.width)
                    page.customHeight = Double(mediaBox.height)
                }
            }
        }

        do {
            try modelContext.save()
        } catch {
            assertionFailure("Failed to save after PDF import: \(error)")
        }
    }

    // MARK: - Image Import

    // Imports an image into a note, creating a single page sized to the image.
    static func importImage(_ image: UIImage, into note: Note, modelContext: ModelContext) {
        guard let imageData = image.pngData() ?? image.jpegData(compressionQuality: 0.9) else { return }

        let pageManager = PageManager(modelContext: modelContext)
        pageManager.insertPage(into: note) { page in
            page.backgroundImageData = imageData
            // Set page dimensions to match the image's pixel size in points.
            page.customWidth = Double(image.size.width)
            page.customHeight = Double(image.size.height)
        }

        do {
            try modelContext.save()
        } catch {
            assertionFailure("Failed to save after image import: \(error)")
        }
    }
}
