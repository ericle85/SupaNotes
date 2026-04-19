import Foundation
import SwiftData

@Model
final class Note {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool = false
    var deletedAt: Date?
    var folder: Folder?
    @Attribute(.externalStorage) var originalPdfData: Data?
    @Relationship(deleteRule: .cascade, inverse: \Page.note) var pages: [Page]

    var sortedPages: [Page] {
        pages.sorted { $0.orderIndex < $1.orderIndex }
    }

    init(title: String = "Untitled Note") {
        self.id = UUID()
        self.title = title
        self.createdAt = .now
        self.updatedAt = .now
        self.pages = [Page(orderIndex: 0)]
    }

    func moveToTrash() {
        isDeleted = true
        deletedAt = .now
    }

    func restore() {
        isDeleted = false
        deletedAt = nil
    }
}
