import Foundation
import PDFKit
import SwiftData
import UIKit

enum PDFService {
    static let pageSize = CGSize(width: 612, height: 792)
    private static let bgRenderScale: CGFloat = 2.0

    // MARK: - Import

    static func importPDF(url: URL, into note: Note, modelContext: ModelContext) {
        guard let data = try? Data(contentsOf: url) else { return }
        importPDF(data: data, into: note, modelContext: modelContext)
    }

    static func importPDF(data: Data, into note: Note, modelContext: ModelContext) {
        guard let doc = PDFDocument(data: data) else { return }

        // Option 1: Store the original PDF data once
        note.originalPdfData = data

        // Remove the default blank page if it's there and empty
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
            // Create a placeholder page that references the PDF
            let page = Page(orderIndex: startIndex + i, template: .white)
            page.note = note
            page.pdfPageNumber = i
            modelContext.insert(page)
        }

        note.updatedAt = .now
        try? modelContext.save()
    }

    // MARK: - Rendering Helpers

    static func imageForPage(_ page: Page) -> UIImage? {
        // 1. If PDF placeholder, render the PDF page to a bitmap for the UI
        if let note = page.note, let pdfData = note.originalPdfData, let pageNum = page.pdfPageNumber {
            if let doc = PDFDocument(data: pdfData), let pdfPage = doc.page(at: pageNum) {
                let pageRect = pdfPage.bounds(for: .mediaBox)
                // Use a standard render scale for UI display
                let targetSize = CGSize(width: pageSize.width * bgRenderScale, height: pageSize.height * bgRenderScale)
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

        // 2. Fallback to bitmap
        if let data = page.backgroundImageData {
            return UIImage(data: data)
        }

        return nil
    }

    private static func rasterize(pdfPage: PDFPage) -> UIImage? {
        let pageRect = pdfPage.bounds(for: .mediaBox)
        let targetSize = CGSize(width: pageSize.width * bgRenderScale, height: pageSize.height * bgRenderScale)
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

    // MARK: - Export

    static func exportNote(_ note: Note, pages: [Page]?) -> Data? {
        let targetPages = pages ?? note.sortedPages
        guard !targetPages.isEmpty else { return nil }

        // Fast path: all pages are unannotated PDF placeholders — return original data as-is
        let allArePDFPlaceholders = targetPages.allSatisfy { $0.pdfPageNumber != nil && $0.drawingData.isEmpty && $0.backgroundImageData == nil }
        if allArePDFPlaceholders, let originalData = note.originalPdfData {
            print("⚡️ Fast path: returning original PDF (\(originalData.count) bytes)")
            return originalData
        }

        print("--- 📝 [Debug] Internal Note Size Breakdown ---")
        let pdfSize = note.originalPdfData?.count ?? 0
        var totalBgSize = 0
        var totalDrawingSize = 0

        for (index, page) in targetPages.enumerated() {
            let bgSize = page.backgroundImageData?.count ?? 0
            let drSize = page.drawingData.count
            totalBgSize += bgSize
            totalDrawingSize += drSize
            print("Page \(index + 1): Raster BG \(bgSize / 1024) KB, Drawing \(drSize / 1024) KB")
        }

        let totalKb = (pdfSize + totalBgSize + totalDrawingSize) / 1024
        print("PDF Source: \(pdfSize / 1024) KB")
        print("Raster BGs: \(totalBgSize / 1024) KB")
        print("All Drawings: \(totalDrawingSize / 1024) KB")
        print("Grand Total Note Footprint: \(totalKb) KB")
        print("---------------------------------------------")

        let bounds = CGRect(origin: .zero, size: pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let data = renderer.pdfData { ctx in
            for page in targetPages {
                ctx.beginPage()
                drawPage(page, in: ctx.cgContext, rect: bounds)
            }
        }

        print("📄 [Debug] Exported PDF size: \(data.count / 1024) KB")
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
    }

    // MARK: - Thumbnail

    static func thumbnail(for page: Page, width: CGFloat) -> UIImage {
        let height = width * (pageSize.height / pageSize.width)
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            drawPage(page, in: ctx.cgContext, rect: CGRect(origin: .zero, size: size))
        }
    }
}
