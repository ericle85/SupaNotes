import Foundation

enum SidebarDestination: Equatable {
    case allNotes
    case folder(Folder)
    case trash
    case settings
    case hwrDemo
    case prototype

    var isAllNotes: Bool { self == .allNotes }
    var isTrash: Bool { self == .trash }
    var isSettings: Bool { self == .settings }

    var folder: Folder? {
        if case .folder(let f) = self { return f }
        return nil
    }

    var isHWRDemo: Bool { self == .hwrDemo }
    var isPrototype: Bool { self == .prototype }

    var showsNoteActions: Bool {
        switch self {
        case .trash, .settings, .hwrDemo, .prototype: return false
        default: return true
        }
    }
}
