import Foundation
import SwiftData

@Model
final class Page {
    var id: UUID
    @Attribute(.externalStorage) var drawingData: Data
    var sortOrder: Int
    var note: Note?

    init(drawingData: Data = Data(), sortOrder: Int = 0) {
        self.id = UUID()
        self.drawingData = drawingData
        self.sortOrder = sortOrder
    }
}
