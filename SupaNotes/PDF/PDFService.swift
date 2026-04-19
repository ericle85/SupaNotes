import Foundation
import PDFKit
import PencilKit
import SwiftData
import UIKit

enum PDFService {
    static let pageSize = CGSize(width: PageConstants.pageWidth, height: PageConstants.pageHeight)
    private static let bgRenderScale: CGFloat = 2.0

    // MARK: - Import
    static func importPDF(url: URL, into note: Note, modelContext: ModelContext) {
        guard let doc = PDFDocument(url: url) else { return }
        let startIndex = note.pages.count
        for i in 0..<doc.pageCount {
            guard let pdfPage = doc.page(at: i) else { continue }
            let image = rasterize(pdfPage: pdfPage)
            let page = Page(orderIndex: startIndex + i, template: .white)
            page.note = note
            page.backgroundImageData = image?.jpegData(compressionQuality: 0.8)
            modelContext.insert(page)
        }
        note.updatedAt = .now
        try? modelContext.save()
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

        let totalDbSize = targetPages.reduce(0) { sum, page in
            sum + (page.backgroundImageData?.count ?? 0) + page.drawingData.count
        }
        print("📝 [Debug] Total internal note size (background + drawing) before PDF export: \(totalDbSize / 1024) KB")

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
        if let data = page.backgroundImageData, let bg = UIImage(data: data) {
            bg.draw(in: rect)
        }
        guard !page.drawingData.isEmpty, let drawing = try? PKDrawing(data: page.drawingData) else { return }
        let strokeRect = CGRect(x: 0, y: 0, width: PageConstants.internalWidth, height: PageConstants.internalHeight)
        var image: UIImage = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: strokeRect, scale: 1.0)
        }
        image.draw(in: rect)
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
