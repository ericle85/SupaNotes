import Foundation
import SwiftData

@Model
final class Folder {
    var id: UUID
    var name: String
    var createdAt: Date
    @Relationship(deleteRule: .nullify, inverse: \Note.folder) var notes: [Note]

    init(name: String = "New Folder") {
        self.id = UUID()
        self.name = name
        self.createdAt = .now
        self.notes = []
    }
}
