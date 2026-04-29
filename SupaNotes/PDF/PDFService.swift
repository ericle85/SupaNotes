import Foundation
import PDFKit
import SwiftData
import UIKit

enum PDFService {
    static let pageSize = CGSize(width: PageConstants.pageWidth, height: PageConstants.pageHeight)
    private static let bgRenderScale: CGFloat = 2.0

    // MARK: - Import

    static func importPDF(url: URL, into note: Note, modelContext: ModelContext) {
        guard let data = try? Data(contentsOf: url) else { return }
        importPDF(data: data, into: note, modelContext: modelContext)
    }

    static func importPDF(data: Data, into note: Note, modelContext: ModelContext) {
        guard let doc = PDFDocument(data: data) else { return }

        // Store the original PDF data once on the note.
        note.originalPdfData = data

        // Remove the default blank page if it's there and empty.
        if note.pages.count == 1,
           let first = note.pages.first,
           first.drawingData.isEmpty,
           first.backgroundImageData == nil
        {
            modelContext.delete(first)
            note.pages = []
        }

        let startIndex = note.pages.count
        for i in 0 ..< doc.pageCount {
            let page = Page(orderIndex: startIndex + i, template: .white)
            page.note = note
            page.pdfPageNumber = i
            // Store the PDF page's native dimensions so the canvas matches.
            if let pdfPage = doc.page(at: i) {
                let mediaBox = pdfPage.bounds(for: .mediaBox)
                page.customWidth = Double(mediaBox.width)
                page.customHeight = Double(mediaBox.height)
            }
            modelContext.insert(page)
        }

        note.updatedAt = .now
        do {
            try modelContext.save()
        } catch {
            assertionFailure("Failed to save after PDF import: \(error)")
        }
    }

    // MARK: - Image Import

    /// Import an image into a note, creating a single page sized to the image.
    static func importImage(_ image: UIImage, into note: Note, modelContext: ModelContext) {
        guard let imageData = image.pngData() ?? image.jpegData(compressionQuality: 0.9) else { return }

        // Remove the default blank page if it's there and empty.
        if note.pages.count == 1,
           let first = note.pages.first,
           first.drawingData.isEmpty,
           first.backgroundImageData == nil
        {
            modelContext.delete(first)
            note.pages = []
        }

        let page = Page(orderIndex: note.pages.count, template: .white)
        page.note = note
        page.backgroundImageData = imageData
        // Set page dimensions to match the image's pixel size in points.
        page.customWidth = Double(image.size.width)
        page.customHeight = Double(image.size.height)
        modelContext.insert(page)

        note.updatedAt = .now
        do {
            try modelContext.save()
        } catch {
            assertionFailure("Failed to save after image import: \(error)")
        }
    }

    // MARK: - Rendering Helpers

    static func imageForPage(_ page: Page) -> UIImage? {
        // 1. If PDF placeholder, render the PDF page to a bitmap for the UI.
        if let note = page.note, let pdfData = note.originalPdfData, let pageNum = page.pdfPageNumber {
            if let doc = PDFDocument(data: pdfData), let pdfPage = doc.page(at: pageNum) {
                let pageRect = pdfPage.bounds(for: .mediaBox)
                // Render at the page's own dimensions scaled for display quality.
                let targetSize = CGSize(width: page.size.width * bgRenderScale, height: page.size.height * bgRenderScale)
                let renderer = UIGraphicsImageRenderer(size: targetSize)
                return renderer.image { ctx in
                    UIColor.white.setFill()
                    ctx.fill(CGRect(origin: .zero, size: targetSize))
                    let cg = ctx.cgContext
                    cg.saveGState()
                    cg.translateBy(x: 0, y: targetSize.height)
                    cg.scaleBy(x: targetSize.width / pageRect.width, y: -targetSize.height / pageRect.height)
                    pdfPage.draw(with: .mediaBox, to: cg)
                    cg.restoreGState()
                }
            }
        }

        // 2. Fallback to bitmap.
        if let data = page.backgroundImageData {
            return UIImage(data: data)
        }

        return nil
    }

    // MARK: - Export

    static func exportNote(_ note: Note, pages: [Page]?) -> Data? {
        let targetPages = pages ?? note.sortedPages
        guard !targetPages.isEmpty else { return nil }

        // Fast path: all pages are unannotated PDF placeholders — return original data as-is
        let allArePDFPlaceholders = targetPages.allSatisfy { $0.pdfPageNumber != nil && $0.drawingData.isEmpty && $0.backgroundImageData == nil }
        if allArePDFPlaceholders, let originalData = note.originalPdfData {
            return originalData
        }

        // Use the first page's size for the renderer bounds; each page overrides via beginPage.
        let defaultBounds = CGRect(origin: .zero, size: targetPages[0].size)
        let renderer = UIGraphicsPDFRenderer(bounds: defaultBounds)
        let data = renderer.pdfData { ctx in
            for page in targetPages {
                // Begin each page with its own dimensions.
                let pageBounds = CGRect(origin: .zero, size: page.size)
                ctx.beginPage(withBounds: pageBounds, pageInfo: [:])
                drawPage(page, in: ctx.cgContext, rect: pageBounds)
            }
        }

        return data
    }

    private static func drawPage(_ page: Page, in ctx: CGContext, rect: CGRect) {
        ctx.setFillColor(page.template.backgroundColor.cgColor)
        ctx.fill(rect)

        // 1. If this is a PDF placeholder page, draw the PDF on-the-fly
        if let note = page.note, let pdfData = note.originalPdfData, let pageNum = page.pdfPageNumber {
            if let doc = PDFDocument(data: pdfData), let pdfPage = doc.page(at: pageNum) {
                ctx.saveGState()
                // Flip coordinate system for PDF drawing
                ctx.translateBy(x: 0, y: rect.height)
                ctx.scaleBy(x: 1, y: -1)

                let pageRect = pdfPage.bounds(for: .mediaBox)
                ctx.scaleBy(x: rect.width / pageRect.width, y: rect.height / pageRect.height)
                pdfPage.draw(with: .mediaBox, to: ctx)
                ctx.restoreGState()
            }
        } else if let data = page.backgroundImageData, let bg = UIImage(data: data) {
            // 2. Fallback to old bitmap background
            bg.draw(in: rect)
        }

        // 3. Draw user strokes on top of the background, using the page's coordinate space.
        let drawing = ExcalidrawPageCodec.decode(data: page.drawingData)
        StrokeRenderer.drawStrokes(from: drawing, in: ctx, rect: rect, pageSize: page.size)
    }

    // MARK: - Thumbnail

    static func thumbnail(for page: Page, width: CGFloat) -> UIImage {
        // Scale height proportionally to the page's actual aspect ratio.
        let height = width * (page.size.height / page.size.width)
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            drawPage(page, in: ctx.cgContext, rect: CGRect(origin: .zero, size: size))
        }
    }
}
