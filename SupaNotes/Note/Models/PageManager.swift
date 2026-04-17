import Foundation
import SwiftData

struct PageManager {
    let modelContext: ModelContext

    private var defaultTemplate: PageTemplate {
        let raw = UserDefaults.standard.string(forKey: "defaultPageTemplate") ?? PageTemplate.white.rawValue
        return PageTemplate(rawValue: raw) ?? .white
    }

    func addPage(to note: Note) {
        let newIndex = note.pages.count
        let page = Page(orderIndex: newIndex, template: defaultTemplate)
        page.note = note
        modelContext.insert(page)
        note.updatedAt = .now
    }

    func addPageAbove(in note: Note) {
        for existingPage in note.pages {
            existingPage.orderIndex += 1
        }
        let page = Page(orderIndex: 0, template: defaultTemplate)
        page.note = note
        modelContext.insert(page)
        note.updatedAt = .now
    }

    func setTemplate(_ template: PageTemplate, for page: Page) {
        page.template = template
        page.note?.updatedAt = .now
    }
}
