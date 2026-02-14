import SwiftUI
import SwiftData

struct NoteListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var notes: [Note]
    var folder: Folder?
    var sortOrder: NoteSortOrder
    var onOpenNote: (UUID) -> Void

    init(folder: Folder?, sortOrder: NoteSortOrder, onOpenNote: @escaping (UUID) -> Void) {
        self.folder = folder
        self.sortOrder = sortOrder
        self.onOpenNote = onOpenNote

        let sortDescriptor: SortDescriptor<Note> = switch sortOrder {
        case .name: SortDescriptor(\Note.title)
        case .lastEdited: SortDescriptor(\Note.updatedAt, order: .reverse)
        case .dateCreated: SortDescriptor(\Note.createdAt, order: .reverse)
        }

        _notes = Query(
            filter: #Predicate<Note> { note in
                note.isDeleted == false
            },
            sort: [sortDescriptor]
        )
    }

    private var filteredNotes: [Note] {
        if let folder {
            return notes.filter { $0.folder?.id == folder.id }
        }
        return notes
    }

    var body: some View {
        if filteredNotes.isEmpty {
            ContentUnavailableView(
                "No Notes",
                systemImage: "note.text",
                description: Text("Tap + to create a new note.")
            )
        } else {
            List {
                ForEach(filteredNotes) { note in
                    Button {
                        onOpenNote(note.id)
                    } label: {
                        NoteRowView(
                            title: note.title,
                            subtitle: note.updatedAt.formatted(.relative(presentation: .named))
                        )
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Delete", role: .destructive) {
                            note.moveToTrash()
                        }
                    }
                    .contextMenu {
                        Button("Rename") {
                            // TODO: Inline rename
                        }
                        Button("Move to Trash", role: .destructive) {
                            note.moveToTrash()
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}
