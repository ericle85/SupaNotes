import Foundation
import SwiftData

@Model
final class NoteTextBox {
    var id: UUID
    var text: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var fontSize: Double
    var note: Note?

    init(text: String = "", x: Double = 0, y: Double = 0, width: Double = 200, height: Double = 60, fontSize: Double = 18) {
        self.id = UUID()
        self.text = text
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.fontSize = fontSize
    }
}
