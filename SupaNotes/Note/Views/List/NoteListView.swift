import SwiftData
import SwiftUI

struct NoteListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TabsState.self) private var tabs

    /// All non-deleted notes from SwiftData, sorted by the chosen order
    @Query private var allNotesFromDatabase: [Note]

    /// All folders, sorted to match the chosen order
    @Query private var allFoldersFromDatabase: [Folder]

    /// The folder the user is viewing (nil = root "All Notes")
    var userSelectedFolder: Folder?

    /// Current sort preference (picker now lives in HomeView)
    var currentNoteSortOrder: NoteSortOrder

    // Navigation callbacks — the parent (HomeView) owns the NavigationStack
    var handleOpeningNote: (UUID) -> Void
    var handleOpeningFolder: (Folder) -> Void

    // Creation callbacks — HomeView owns the model context and file pickers
    var handleCreateNote: () -> Void
    var handleCreateFolder: (() -> Void)?
    var handleImportPDF: () -> Void
    var handleImportImage: () -> Void

    // Rename state — uses alerts instead of inline editing (grid tiles can't host text fields)
    @State private var noteToRename: Note?
    @State private var renameText = ""
    @State private var folderToRename: Folder?
    @State private var folderRenameText = ""
    @State private var folderToDelete: Folder?

    // Adaptive grid: ~6–7 columns on iPad landscape, fewer on smaller screens
    private let gridColumns = [
        GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 20),
    ]

    // Standard page aspect ratio for consistent tile proportions
    private let pageAspect = PageConstants.pageWidth / PageConstants.pageHeight

    init(
        folder: Folder?,
        sortOrder: NoteSortOrder,
        onOpenNote: @escaping (UUID) -> Void,
        onOpenFolder: @escaping (Folder) -> Void,
        onCreateNote: @escaping () -> Void,
        onCreateFolder: (() -> Void)? = nil,
        onImportPDF: @escaping () -> Void,
        onImportImage: @escaping () -> Void
    ) {
        userSelectedFolder = folder
        currentNoteSortOrder = sortOrder
        handleOpeningNote = onOpenNote
        handleOpeningFolder = onOpenFolder
        handleCreateNote = onCreateNote
        handleCreateFolder = onCreateFolder
        handleImportPDF = onImportPDF
        handleImportImage = onImportImage

        // SwiftData queries are configured once at init; changing sortOrder recreates the view
        _allNotesFromDatabase = Query(
            filter: #Predicate<Note> { note in note.isDeleted == false },
            sort: [sortOrder.noteSort]
        )
        _allFoldersFromDatabase = Query(sort: [sortOrder.folderSort])
    }

    /// Filters the full note list down to what belongs in the current folder
    private var notesInSelectedFolder: [Note] {
        allNotesFromDatabase.filter { note in
            if let currentFolder = userSelectedFolder {
                // Inside a folder — show only its notes
                return note.folder?.id == currentFolder.id
            } else {
                // At root — show only un-foldered notes
                return note.folder == nil
            }
        }
    }

    /// Whether we're at root level (not inside any folder)
    private var isAtRootLevel: Bool {
        userSelectedFolder == nil
    }

    // MARK: - Body

    var body: some View {
        // The filter bar lives in HomeView so it stays fixed during folder transitions
        noteGrid
        // Rename-note alert with text field
        .alert("Rename Note", isPresented: isRenamingNote) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { noteToRename = nil }
            Button("Save") { commitNoteRename() }
        }
        // Rename-folder alert with text field
        .alert("Rename Folder", isPresented: isRenamingFolder) {
            TextField("Name", text: $folderRenameText)
            Button("Cancel", role: .cancel) { folderToRename = nil }
            Button("Save") { commitFolderRename() }
        }
        // Delete-folder confirmation (only shown when folder has notes)
        .alert(
            "Delete \"\(folderToDelete?.name ?? "")\"?",
            isPresented: isDeletingFolder,
            presenting: folderToDelete
        ) { folder in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { permanentlyDeleteFolder(folder) }
        } message: { folder in
            Text("This folder contains \(countLiveNotesIn(folder)) notes. They will be moved to trash.")
        }
    }

    // MARK: - Grid

    /// The main scrollable grid of "New...", folder, and note tiles
    private var noteGrid: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 24) {
                // "New..." tile is always first
                newNoteTile

                // Folders appear at root level, before notes
                if isAtRootLevel {
                    ForEach(allFoldersFromDatabase) { folder in
                        folderTile(for: folder)
                    }
                }

                // Note tiles with thumbnails
                ForEach(notesInSelectedFolder) { note in
                    NoteTileView(
                        note: note,
                        onOpen: { handleOpeningNote(note.id) },
                        onRename: { beginRenamingNote(note) },
                        onDelete: {
                            tabs.close(noteID: note.id)
                            note.moveToTrash()
                        }
                    )
                }
            }
            .padding(20)
        }
    }

    // MARK: - New Tile

    /// Dashed-border tile that opens a creation menu (new note, folder, import)
    private var newNoteTile: some View {
        Menu {
            Button { handleCreateNote() } label: {
                Label("New Note", systemImage: "doc")
            }
            if let createFolder = handleCreateFolder {
                Button { createFolder() } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
            }
            Divider()
            Button { handleImportPDF() } label: {
                Label("Import PDF", systemImage: "doc.richtext")
            }
            Button { handleImportImage() } label: {
                Label("Import Image", systemImage: "photo")
            }
        } label: {
            VStack(spacing: 6) {
                // Dashed rectangle matching the tile thumbnail area
                RoundedRectangle(cornerRadius: Design.CornerRadius.small)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    .foregroundStyle(Color.accentColor)
                    .aspectRatio(pageAspect, contentMode: .fit)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(Color.accentColor)
                    }

                // Label under the dashed box
                Text("New...")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.accentColor)

                // Invisible spacer text so vertical alignment matches note tiles (which have a date)
                Text(" ")
                    .font(.caption2)
            }
        }
    }

    // MARK: - Folder Tile

    /// A grid tile for a folder — shows a folder icon and note count as its "thumbnail"
    private func folderTile(for folder: Folder) -> some View {
        VStack(spacing: 6) {
            // Tappable area that navigates into the folder
            Button { handleOpeningFolder(folder) } label: {
                RoundedRectangle(cornerRadius: Design.CornerRadius.small)
                    .fill(Color(.systemGray5))
                    .aspectRatio(pageAspect, contentMode: .fit)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            Text("\(countLiveNotesIn(folder)) notes")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
            }
            .buttonStyle(.plain)

            // Folder name with dropdown for rename / delete
            Menu {
                Button("Rename") { beginRenamingFolder(folder) }
                Button("Delete", role: .destructive) { askUserToDeleteFolder(folder) }
            } label: {
                HStack(spacing: 2) {
                    Text(folder.name)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                }
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Color.accentColor)
            }

            // Folder creation date
            Text(folder.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Empty State

    private var emptyStatePlaceholder: some View {
        ContentUnavailableView(
            "No Notes",
            systemImage: "note.text",
            description: Text("Tap New to create a note.")
        )
    }

    // MARK: - Rename Helpers

    private var isRenamingNote: Binding<Bool> {
        Binding(get: { noteToRename != nil }, set: { if !$0 { noteToRename = nil } })
    }

    private var isRenamingFolder: Binding<Bool> {
        Binding(get: { folderToRename != nil }, set: { if !$0 { folderToRename = nil } })
    }

    private var isDeletingFolder: Binding<Bool> {
        Binding(get: { folderToDelete != nil }, set: { if !$0 { folderToDelete = nil } })
    }

    private func beginRenamingNote(_ note: Note) {
        renameText = note.title
        noteToRename = note
    }

    private func commitNoteRename() {
        guard let note = noteToRename else { return }
        note.title = renameText
        noteToRename = nil
    }

    private func beginRenamingFolder(_ folder: Folder) {
        folderRenameText = folder.name
        folderToRename = folder
    }

    private func commitFolderRename() {
        guard let folder = folderToRename else { return }
        folder.name = folderRenameText
        folderToRename = nil
    }

    // MARK: - Folder Actions

    private func countLiveNotesIn(_ folder: Folder) -> Int {
        folder.notes.filter { !$0.isDeleted }.count
    }

    private func askUserToDeleteFolder(_ folder: Folder) {
        if countLiveNotesIn(folder) > 0 {
            folderToDelete = folder
        } else {
            permanentlyDeleteFolder(folder)
        }
    }

    private func permanentlyDeleteFolder(_ folder: Folder) {
        // Trash all notes inside the folder first
        for note in folder.notes where !note.isDeleted {
            tabs.close(noteID: note.id)
            note.moveToTrash()
        }
        modelContext.delete(folder)
    }
}
