import Foundation
import SwiftData

struct PageManager {
    let modelContext: ModelContext

    func addPage(to note: Note) {
        let newIndex = note.pages.count
        let page = Page(orderIndex: newIndex)
        page.note = note
        modelContext.insert(page)
        note.updatedAt = .now
    }

    func addPageAbove(in note: Note) {
        for existingPage in note.pages {
            existingPage.orderIndex += 1
        }
        let page = Page(orderIndex: 0)
        page.note = note
        modelContext.insert(page)
        note.updatedAt = .now
    }
}
