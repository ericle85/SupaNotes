import Foundation
import SwiftData

@Model
final class Page {
    var id: UUID
    var orderIndex: Int
    @Attribute(.externalStorage) var drawingData: Data
    var note: Note?

    init(orderIndex: Int = 0, drawingData: Data = Data()) {
        self.id = UUID()
        self.orderIndex = orderIndex
        self.drawingData = drawingData
    }
}
