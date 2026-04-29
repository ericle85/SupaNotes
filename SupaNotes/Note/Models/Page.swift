import Foundation
import SwiftData

@Model
final class Page {
    var id: UUID
    var orderIndex: Int
    @Attribute(.externalStorage) var drawingData: Data
    // Legacy compatibility for drawings saved before fixed page coordinates.
    var drawingScale: Double?
    @Attribute(.externalStorage) var backgroundImageData: Data?
    var pdfPageNumber: Int?
    var templateRaw: String?
    var isBookmarked: Bool = false
    var note: Note?
    // Per-page dimensions for imported content (nil = default letter size).
    var customWidth: Double?
    var customHeight: Double?

    // The coordinate space for this page's strokes and layout.
    var size: CGSize {
        CGSize(
            width: customWidth ?? Double(PageConstants.pageWidth),
            height: customHeight ?? Double(PageConstants.pageHeight)
        )
    }

    var template: PageTemplate {
        get { PageTemplate(rawValue: templateRaw ?? "") ?? .white }
        set { templateRaw = newValue.rawValue }
    }

    init(orderIndex: Int = 0, drawingData: Data = Data(), template: PageTemplate = .white) {
        id = UUID()
        self.orderIndex = orderIndex
        self.drawingData = drawingData
        drawingScale = 1.0
        templateRaw = template.rawValue
    }
}
