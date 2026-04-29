import Foundation

enum SidebarDestination: Hashable {
    case allNotes
    case folder(Folder)
    case trash
    case settings

    var isAllNotes: Bool {
        self == .allNotes
    }

    var isTrash: Bool {
        self == .trash
    }

    var isSettings: Bool {
        self == .settings
    }

    var folder: Folder? {
        if case let .folder(f) = self { return f }
        return nil
    }

    var showsNoteActions: Bool {
        switch self {
        case .trash, .settings: return false
        default: return true
        }
    }
}
