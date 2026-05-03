import Foundation
import SwiftData

// Where to insert a new page relative to existing pages.
enum PageInsertPosition {
    // Append after the last page (or create as first if empty).
    case end
    // Insert above the page at the given order index, shifting it and everything below down.
    case above(Int)
    // Insert below the page at the given order index, shifting everything after it down.
    case below(Int)
}

struct PageManager {
    let modelContext: ModelContext

    private var defaultTemplate: PageTemplate {
        let raw = UserDefaults.standard.string(forKey: "defaultPageTemplate") ?? PageTemplate.white.rawValue
        return PageTemplate(rawValue: raw) ?? .white
    }

    // MARK: - Core

    // All page creation goes through here. The optional configure closure lets
    // callers set custom properties (PDF dimensions, background image, etc.)
    // before the page is inserted into the context.
    func insertPage(
        into note: Note,
        at position: PageInsertPosition = .end,
        configure: ((Page) -> Void)? = nil
    ) {
        let newIndex: Int

        switch position {
        case .end:
            // Place after the last existing page.
            newIndex = (note.sortedPages.last?.orderIndex ?? -1) + 1

        case .above(let orderIndex):
            // Shift every page at or after this index down by one.
            for page in note.pages where page.orderIndex >= orderIndex {
                page.orderIndex += 1
            }
            newIndex = orderIndex

        case .below(let orderIndex):
            // Shift every page after this index down by one.
            for page in note.pages where page.orderIndex > orderIndex {
                page.orderIndex += 1
            }
            newIndex = orderIndex + 1
        }

        let page = Page(orderIndex: newIndex, template: defaultTemplate)
        configure?(page)
        page.note = note
        modelContext.insert(page)
        note.updatedAt = .now
    }

    // MARK: - Convenience

    // Inserts a blank page at the specified position. Default appends to end.
    func addPage(to note: Note, at position: PageInsertPosition = .end) {
        insertPage(into: note, at: position)
    }

    // TODO: Move page to trash function should be written here if I do choose to write it.
}
