import Foundation
import PDFKit
import UIKit

// Exports a Note's pages to PDF data.
enum PDFExporter {

    // Renders the given pages (or all pages in the note) to a PDF Data blob.
    // Returns the original PDF data unchanged when all pages are unannotated PDF placeholders.
    static func exportNote(_ note: Note, pages: [Page]?) -> Data? {
        let targetPages = pages ?? note.sortedPages
        guard !targetPages.isEmpty else { return nil }

        // Fast path: all pages are unannotated PDF placeholders — return original data as-is.
        let allArePDFPlaceholders = targetPages.allSatisfy {
            $0.pdfPageNumber != nil && $0.drawingData.isEmpty && $0.backgroundImageData == nil
        }
        if allArePDFPlaceholders, let originalData = note.originalPdfData {
            return originalData
        }

        // Render each page into a new PDF document.
        let defaultBounds = CGRect(origin: .zero, size: targetPages[0].size)
        let renderer = UIGraphicsPDFRenderer(bounds: defaultBounds)
        let data = renderer.pdfData { ctx in
            for page in targetPages {
                // Begin each page with its own dimensions.
                let pageBounds = CGRect(origin: .zero, size: page.size)
                ctx.beginPage(withBounds: pageBounds, pageInfo: [:])
                PageRenderer.drawPage(page, in: ctx.cgContext, rect: pageBounds)
            }
        }

        return data
    }
}
