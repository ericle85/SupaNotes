import SwiftUI
import SwiftData

struct NoteListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TabsState.self) private var tabs
    @Query private var notes: [Note]
    @Query(sort: \Folder.createdAt) private var folders: [Folder]
    var folder: Folder?
    var sortOrder: NoteSortOrder
    var onOpenNote: (UUID) -> Void
    var onOpenFolder: (Folder) -> Void

    @State private var editingFolder: Folder?
    @State private var editingName: String = ""
    @State private var pendingDeleteFolder: Folder?

    init(
        folder: Folder?,
        sortOrder: NoteSortOrder,
        onOpenNote: @escaping (UUID) -> Void,
        onOpenFolder: @escaping (Folder) -> Void
    ) {
        self.folder = folder
        self.sortOrder = sortOrder
        self.onOpenNote = onOpenNote
        self.onOpenFolder = onOpenFolder

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
        return notes.filter { $0.folder == nil }
    }

    private var showsFolders: Bool { folder == nil }

    var body: some View {
        if filteredNotes.isEmpty && (!showsFolders || folders.isEmpty) {
            ContentUnavailableView(
                "No Notes",
                systemImage: "note.text",
                description: Text("Tap + to create a new note.")
            )
        } else {
            List {
                if showsFolders {
                    ForEach(folders) { folder in
                        folderRow(folder)
                    }
                }
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
                            tabs.close(noteID: note.id)
                            note.moveToTrash()
                        }
                    }
                    .contextMenu {
                        Button("Move to Trash", role: .destructive) {
                            tabs.close(noteID: note.id)
                            note.moveToTrash()
                        }
                    }
                }
            }
            .listStyle(.plain)
            .alert(
                "Delete \"\(pendingDeleteFolder?.name ?? "")\"?",
                isPresented: Binding(
                    get: { pendingDeleteFolder != nil },
                    set: { if !$0 { pendingDeleteFolder = nil } }
                ),
                presenting: pendingDeleteFolder
            ) { folder in
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    deleteFolder(folder)
                }
            } message: { folder in
                Text("This folder contains \(liveNoteCount(folder)) notes. They will be moved to trash.")
            }
        }
    }

    private func liveNoteCount(_ folder: Folder) -> Int {
        folder.notes.filter { !$0.isDeleted }.count
    }

    private func requestDelete(_ folder: Folder) {
        if liveNoteCount(folder) > 0 {
            pendingDeleteFolder = folder
        } else {
            deleteFolder(folder)
        }
    }

    private func deleteFolder(_ folder: Folder) {
        for note in folder.notes where !note.isDeleted {
            tabs.close(noteID: note.id)
            note.moveToTrash()
        }
        modelContext.delete(folder)
    }

    @ViewBuilder
    private func folderRow(_ folder: Folder) -> some View {
        if editingFolder?.id == folder.id {
            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                TextField("Folder name", text: $editingName)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        folder.name = editingName
                        editingFolder = nil
                    }
            }
        } else {
            Button {
                onOpenFolder(folder)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text(folder.name)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(folder.notes.filter { !$0.isDeleted }.count)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .swipeActions(edge: .trailing) {
                Button("Delete", role: .destructive) {
                    requestDelete(folder)
                }
                Button("Rename") {
                    editingName = folder.name
                    editingFolder = folder
                }
                .tint(.blue)
            }
            .contextMenu {
                Button("Rename") {
                    editingName = folder.name
                    editingFolder = folder
                }
                Button("Delete", role: .destructive) {
                    requestDelete(folder)
                }
            }
        }
    }
}
