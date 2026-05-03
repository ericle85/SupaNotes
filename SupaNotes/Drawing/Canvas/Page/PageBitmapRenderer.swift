import PDFKit
import UIKit

// Renders a low-resolution UIImage snapshot of a Page — paper or PDF/image
// background composited under the page's flattened strokes. Used for slots
// that don't currently host the live DrawingCanvasView; they show this
// snapshot so the user still sees their drawings while scrolling.
//
// Synchronous and pure. No caching here: each PageSlotView holds the only
// reference to its bitmap, so when a slot is torn down on rebuild the bitmap
// goes with it.
enum PageBitmapRenderer {

    // Default render scale: 0.5× of the page's coordinate space. Big enough
    // to look acceptable on the typical iPad page width, small enough that
    // 500 of these don't blow up memory.
    static let defaultScale: CGFloat = 0.5

    // Render a page snapshot. Returns a UIImage sized to the page's layout
    // size at the requested scale.
    static func render(page: Page, scale: CGFloat = defaultScale) -> UIImage {
        let size = page.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            let cgctx = context.cgContext
            let pageRect = CGRect(origin: .zero, size: size)
            drawBackground(page: page, in: cgctx, rect: pageRect)
            drawStrokes(page: page, in: cgctx, rect: pageRect)
        }
    }

    // MARK: - Background

    // Mirrors DrawingCanvasView.applyAppearance: PDF page > raster image > template color.
    private static func drawBackground(page: Page, in context: CGContext, rect: CGRect) {
        if let pdfPage = pdfPage(for: page) {
            // White underlay so transparent PDFs look right.
            context.setFillColor(UIColor.white.cgColor)
            context.fill(rect)
            let mediaBox = pdfPage.bounds(for: .mediaBox)
            context.saveGState()
            // PDF coordinate system is bottom-up; flip to match UIKit.
            context.translateBy(x: 0, y: rect.height)
            context.scaleBy(x: rect.width / mediaBox.width, y: -rect.height / mediaBox.height)
            pdfPage.draw(with: .mediaBox, to: context)
            context.restoreGState()
            return
        }
        if let imageData = page.backgroundImageData, let image = UIImage(data: imageData) {
            image.draw(in: rect)
            return
        }
        // Plain template paper color.
        page.template.backgroundColor.setFill()
        context.fill(rect)
    }

    // Walk the page → note → originalPdfData chain to find the matching PDF page.
    private static func pdfPage(for page: Page) -> PDFPage? {
        guard let note = page.note,
              let pageNum = page.pdfPageNumber,
              let doc = PDFDocumentCache.document(for: note),
              let pdfPage = doc.page(at: pageNum)
        else { return nil }
        return pdfPage
    }

    // MARK: - Strokes

    // Decode and rasterize the page's saved strokes via the shared renderer.
    private static func drawStrokes(page: Page, in context: CGContext, rect: CGRect) {
        let drawing = DrawingCodec.decode(data: page.drawingData)
        guard !drawing.strokes.isEmpty else { return }
        StrokeRenderer.drawStrokes(from: drawing, in: context, rect: rect, pageSize: page.size)
    }
}
