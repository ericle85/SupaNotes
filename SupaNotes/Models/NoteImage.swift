import Foundation
import SwiftData

@Model
final class NoteImage {
    var id: UUID
    @Attribute(.externalStorage) var imageData: Data
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var note: Note?

    init(imageData: Data, x: Double = 0, y: Double = 0, width: Double = 250, height: Double = 250) {
        self.id = UUID()
        self.imageData = imageData
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}
