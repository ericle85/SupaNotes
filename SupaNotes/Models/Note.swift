import Foundation
import SwiftData

@Model
final class Note {
    var id: UUID
    var title: String
    @Attribute(.externalStorage) var drawingData: Data
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \NoteImage.note) var images: [NoteImage] = []
    @Relationship(deleteRule: .cascade, inverse: \NoteTextBox.note) var textBoxes: [NoteTextBox] = []

    init(title: String = "Untitled Note", drawingData: Data = Data()) {
        self.id = UUID()
        self.title = title
        self.drawingData = drawingData
        self.createdAt = .now
        self.updatedAt = .now
    }
}
