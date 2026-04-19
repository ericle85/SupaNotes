import Foundation
import SwiftData

@Model
final class Page {
    var id: UUID
    var orderIndex: Int
    @Attribute(.externalStorage) var drawingData: Data
    @Attribute(.externalStorage) var backgroundImageData: Data?
    var pdfPageNumber: Int?
    var templateRaw: String?
    var isBookmarked: Bool = false
    var note: Note?

    var template: PageTemplate {
        get { PageTemplate(rawValue: templateRaw ?? "") ?? .white }
        set { templateRaw = newValue.rawValue }
    }

    init(orderIndex: Int = 0, drawingData: Data = Data(), template: PageTemplate = .white) {
        self.id = UUID()
        self.orderIndex = orderIndex
        self.drawingData = drawingData
        self.templateRaw = template.rawValue
    }
}
