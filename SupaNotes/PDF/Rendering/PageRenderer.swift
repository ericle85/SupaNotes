import Foundation
import PDFKit
import UIKit

// Renders a single Page to a CGContext, UIImage, or thumbnail.
// Shared by PDFExporter (vector export) and UI code (bitmap thumbnails).
enum PageRenderer {
    private static let bgRenderScale: CGFloat = 2.0

    // MARK: - Core draw

    // Draws a page's background (PDF, image, or template color) plus user strokes
    // into the given CGContext at `rect` size.
    static func drawPage(_ page: Page, in ctx: CGContext, rect: CGRect) {
        // Fill with template background color.
        ctx.setFillColor(page.template.backgroundColor.cgColor)
        ctx.fill(rect)

        // Draw the page's background content — either a PDF page or a bitmap image.
        if let note = page.note, let pdfData = note.originalPdfData, let pageNum = page.pdfPageNumber {
            if let doc = PDFDocument(data: pdfData), let pdfPage = doc.page(at: pageNum) {
                ctx.saveGState()
                // Flip coordinate system for PDF drawing.
                ctx.translateBy(x: 0, y: rect.height)
                ctx.scaleBy(x: 1, y: -1)

                let pageRect = pdfPage.bounds(for: .mediaBox)
                ctx.scaleBy(x: rect.width / pageRect.width, y: rect.height / pageRect.height)
                pdfPage.draw(with: .mediaBox, to: ctx)
                ctx.restoreGState()
            }
        } else if let data = page.backgroundImageData, let bg = UIImage(data: data) {
            bg.draw(in: rect)
        }

        // Draw user strokes on top of the background, using the page's coordinate space.
        let drawing = DrawingCodec.decode(data: page.drawingData)
        StrokeRenderer.drawStrokes(from: drawing, in: ctx, rect: rect, pageSize: page.size)
    }

    // MARK: - Bitmap rendering

    // Renders the page's background as a UIImage for display in the canvas.
    // Returns nil when the page has no visual background.
    static func imageForPage(_ page: Page) -> UIImage? {
        // If this is a PDF placeholder page, render the PDF page to a bitmap.
        if let note = page.note, let pdfData = note.originalPdfData, let pageNum = page.pdfPageNumber {
            if let doc = PDFDocument(data: pdfData), let pdfPage = doc.page(at: pageNum) {
                let pageRect = pdfPage.bounds(for: .mediaBox)
                let targetSize = CGSize(
                    width: page.size.width * bgRenderScale,
                    height: page.size.height * bgRenderScale
                )
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

        // Fallback to stored bitmap background.
        if let data = page.backgroundImageData {
            return UIImage(data: data)
        }

        return nil
    }

    // MARK: - Thumbnail

    // Renders a scaled-down bitmap of the full page (background + strokes).
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
