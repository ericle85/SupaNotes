import SwiftData
import SwiftUI

struct NoteListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TabsState.self) private var tabs

    /// A list of all notes, sorted and filtered by the database (SwiftData)
    @Query private var allNotesFromDatabase: [Note]

    /// A list of all folders, sorted to match the user's preference
    @Query private var allFoldersFromDatabase: [Folder]

    /// The specific folder the user is looking at. If this is nil, we are at the "All Notes" root.
    var userSelectedFolder: Folder?

    /// How the notes should be ordered in the list
    var currentNoteSortOrder: NoteSortOrder

    /// A function (closure) to call when the user taps on a note
    var handleOpeningNote: (UUID) -> Void

    /// A function (closure) to call when the user taps on a folder
    var handleOpeningFolder: (Folder) -> Void

    @State private var folderBeingRenamed: Folder?
    @State private var newNameForFolder: String = ""
    @State private var folderThatIsAboutToBeDeleted: Folder?

    init(
        folder: Folder?,
        sortOrder: NoteSortOrder,
        onOpenNote: @escaping (UUID) -> Void,
        onOpenFolder: @escaping (Folder) -> Void
    ) {
        userSelectedFolder = folder
        currentNoteSortOrder = sortOrder
        handleOpeningNote = onOpenNote
        handleOpeningFolder = onOpenFolder

        // Decide how to sort notes based on the user's preference
        let noteSortDescriptor: SortDescriptor<Note> = switch sortOrder {
        case .name: SortDescriptor(\Note.title)
        case .lastEdited: SortDescriptor(\Note.updatedAt, order: .reverse)
        case .dateCreated: SortDescriptor(\Note.createdAt, order: .reverse)
        }

        // Only fetch notes that are NOT in the trash (isDeleted == false)
        _allNotesFromDatabase = Query(
            filter: #Predicate<Note> { note in
                note.isDeleted == false
            },
            sort: [noteSortDescriptor]
        )

        // Decide how to sort folders to match. Since folders don't have a "last edited"
        // property, we fall back to "date created" for that case.
        let folderSortDescriptor: SortDescriptor<Folder> = switch sortOrder {
        case .name: SortDescriptor(\Folder.name)
        case .lastEdited, .dateCreated: SortDescriptor(\Folder.createdAt, order: .reverse)
        }

        _allFoldersFromDatabase = Query(sort: [folderSortDescriptor])
    }

    /// Returns only the notes that should be shown in the current folder view
    private var notesInSelectedFolder: [Note] {
        allNotesFromDatabase.filter { note in
            if let currentFolder = userSelectedFolder {
                // We are inside a folder, so only show notes that belong to it
                return note.folder?.id == currentFolder.id
            } else {
                // We are at the root (All Notes), so only show notes that have NO folder
                return note.folder == nil
            }
        }
    }

    /// Helper to check if we are at the top level (not inside any folder)
    private var isAtRootLevel: Bool {
        userSelectedFolder == nil
    }

    var body: some View {
        if notesInSelectedFolder.isEmpty && (!isAtRootLevel || allFoldersFromDatabase.isEmpty) {
            emptyStatePlaceholderView
        } else {
            notesAndFoldersList
        }
    }

    private var emptyStatePlaceholderView: some View {
        ContentUnavailableView(
            "No Notes",
            systemImage: "note.text",
            description: Text("Tap + to create a new note.")
        )
    }

    private var notesAndFoldersList: some View {
        List {
            // Show the notes for the current view first
            ForEach(notesInSelectedFolder) { note in
                noteRow(for: note)
            }

            // Then show folders if we are at the top level
            if isAtRootLevel {
                ForEach(allFoldersFromDatabase) { folder in
                    folderRow(for: folder)
                }
            }
        }
        .listStyle(.plain)
        .alert(
            "Delete \"\(folderThatIsAboutToBeDeleted?.name ?? "")\"?",
            isPresented: isDeleteAlertShowing,
            presenting: folderThatIsAboutToBeDeleted
        ) { folder in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                permanentlyDeleteFolder(folder)
            }
        } message: { folder in
            Text("This folder contains \(countLiveNotesIn(folder)) notes. They will be moved to trash.")
        }
    }

    private var isDeleteAlertShowing: Binding<Bool> {
        Binding(
            get: { folderThatIsAboutToBeDeleted != nil },
            set: { if !$0 { folderThatIsAboutToBeDeleted = nil } }
        )
    }

    private func noteRow(for note: Note) -> some View {
        Button {
            handleOpeningNote(note.id)
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

    @ViewBuilder
    private func folderRow(for folder: Folder) -> some View {
        if folderBeingRenamed?.id == folder.id {
            folderEditingRow(for: folder)
        } else {
            folderNormalRow(for: folder)
        }
    }

    private func folderEditingRow(for folder: Folder) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            TextField("Folder name", text: $newNameForFolder)
                .textFieldStyle(.plain)
                .onSubmit {
                    folder.name = newNameForFolder
                    folderBeingRenamed = nil
                }
        }
    }

    private func folderNormalRow(for folder: Folder) -> some View {
        Button {
            handleOpeningFolder(folder)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(folder.name)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(countLiveNotesIn(folder))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", role: .destructive) {
                askUserToDeleteFolder(folder)
            }
            Button("Rename") {
                beginRenamingFolder(folder)
            }
            .tint(.blue)
        }
        .contextMenu {
            Button("Rename") {
                beginRenamingFolder(folder)
            }
            Button("Delete", role: .destructive) {
                askUserToDeleteFolder(folder)
            }
        }
    }

    private func beginRenamingFolder(_ folder: Folder) {
        newNameForFolder = folder.name
        folderBeingRenamed = folder
    }

    private func countLiveNotesIn(_ folder: Folder) -> Int {
        // Only count notes that aren't in the trash
        folder.notes.filter { note in !note.isDeleted }.count
    }

    private func askUserToDeleteFolder(_ folder: Folder) {
        // If the folder has notes, we show an alert. If it's empty, we just delete it.
        if countLiveNotesIn(folder) > 0 {
            folderThatIsAboutToBeDeleted = folder
        } else {
            permanentlyDeleteFolder(folder)
        }
    }

    private func permanentlyDeleteFolder(_ folder: Folder) {
        // Move all notes in this folder to the trash first
        for note in folder.notes where !note.isDeleted {
            tabs.close(noteID: note.id)
            note.moveToTrash()
        }
        // Then delete the folder itself
        modelContext.delete(folder)
    }
}
