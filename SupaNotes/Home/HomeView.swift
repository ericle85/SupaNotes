import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum NoteSortOrder: String, CaseIterable {
    // Order here controls the segmented picker left-to-right
    case lastEdited = "Last Edited"
    case name = "Name"
    case dateCreated = "Date Created"

    /// How to sort Note objects in the database for this order.
    var noteSort: SortDescriptor<Note> {
        switch self {
        case .name: SortDescriptor(\Note.title)
        case .lastEdited: SortDescriptor(\Note.updatedAt, order: .reverse)
        case .dateCreated: SortDescriptor(\Note.createdAt, order: .reverse)
        }
    }

    /// How to sort Folder objects for this order.
    /// Folders have no "last edited" date, so that case falls back to creation date.
    var folderSort: SortDescriptor<Folder> {
        switch self {
        case .name: SortDescriptor(\Folder.name)
        case .lastEdited, .dateCreated: SortDescriptor(\Folder.createdAt, order: .reverse)
        }
    }

    /// Short labels for the segmented picker in the grid filter bar
    var shortLabel: String {
        switch self {
        case .name: "Name"
        case .lastEdited: "Last Edited"
        case .dateCreated: "Date Created"
        }
    }
}

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext

    /// Tracks which section of the app we are currently looking at (e.g. All Notes, Trash, Settings)
    @State private var currentViewInApp: SidebarDestination = .allNotes

    /// The sorting order for the list of notes
    @State private var selectedNoteSortOrder: NoteSortOrder = .lastEdited

    /// A stack of note IDs that the user has opened. This allows navigation between views.
    @State private var noteNavigationStack = NavigationPath()

    /// Manages the state of currently open notes in tabs
    @State private var openTabsState = TabsState()

    /// Whether the PDF file picker is showing.
    @State private var isShowingPDFPicker = false
    /// Whether the photo picker is showing.
    @State private var isShowingPhotoPicker = false
    /// The selected photo item from the picker.
    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        // NavigationStack is the container that allows us to move between different screens
        NavigationStack(path: $noteNavigationStack) {
            VStack(spacing: 0) {
                // The top bar of the app containing the title and actions
                appTopNavigationBar

                Divider()

                // Display the correct view based on what the user has selected
                mainContentArea
            }
            .background(Color("PaperBackground"))
            .navigationBarHidden(true)
            // This tells the app how to show a note when one is selected
            .navigationDestination(for: UUID.self) { noteID in
                TabbedEditorRoot(initialID: noteID)
            }
        }
        .environment(openTabsState)
        // PDF file picker.
        .fileImporter(
            isPresented: $isShowingPDFPicker,
            allowedContentTypes: [UTType.pdf],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                // Request access to the security-scoped resource.
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                importPDF(from: url)
            }
        }
        // Photo picker for image import.
        .photosPicker(isPresented: $isShowingPhotoPicker, selection: $selectedPhotoItem, matching: .images)
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data)
                {
                    importImage(image)
                }
            }
            selectedPhotoItem = nil
        }
    }

    @ViewBuilder
    private var mainContentArea: some View {
        switch currentViewInApp {
        case .trash:
            TrashView()
        case .settings:
            SettingsView()
        case .allNotes, .folder:
            VStack(spacing: 0) {
                // Filter bar stays fixed outside the transition
                sortFilterBar

                noteGridForCurrentView
            }
        }
    }

    /// Segmented sort picker — sits above the grid and stays static during folder transitions
    private var sortFilterBar: some View {
        HStack {
            Spacer()
            Picker("Sort", selection: $selectedNoteSortOrder) {
                ForEach(NoteSortOrder.allCases, id: \.self) { order in
                    Text(order.shortLabel).tag(order)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    /// Builds the correct NoteListView for root or folder
    @ViewBuilder
    private var noteGridForCurrentView: some View {
        switch currentViewInApp {
        case .allNotes:
            NoteListView(
                folder: nil,
                sortOrder: selectedNoteSortOrder,

                onOpenNote: { noteID in noteNavigationStack.append(noteID) },
                onOpenFolder: { folder in currentViewInApp = .folder(folder) },
                onCreateNote: { createNewNote() },
                onCreateFolder: {
                    let newFolder = Folder()
                    modelContext.insert(newFolder)
                },
                onImportPDF: { isShowingPDFPicker = true },
                onImportImage: { isShowingPhotoPicker = true }
            )
        case let .folder(folder):
            NoteListView(
                folder: folder,
                sortOrder: selectedNoteSortOrder,

                onOpenNote: { noteID in noteNavigationStack.append(noteID) },
                onOpenFolder: { folder in currentViewInApp = .folder(folder) },
                onCreateNote: { createNewNote() },
                onImportPDF: { isShowingPDFPicker = true },
                onImportImage: { isShowingPhotoPicker = true }
            )
        default:
            EmptyView()
        }
    }

    private var appTopNavigationBar: some View {
        HStack(spacing: 12) {
            backButtonIfShowingSubView

            Text(titleForCurrentView)
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            // If we are in a note-related view, show buttons to add folders or notes
            if currentViewInApp.showsNoteActions {
                noteRelatedActionButtons
            }
        }
        .padding(.horizontal, Design.Spacing.headerHorizontal)
        .padding(.vertical, Design.Spacing.headerVertical)
    }

    @ViewBuilder
    private var backButtonIfShowingSubView: some View {
        // If we are not on the main "All Notes" screen, show a way to go back
        if currentViewInApp != .allNotes {
            Button {
                currentViewInApp = .allNotes
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: Design.FontSize.headerIcon))
                    .foregroundStyle(.primary)
                    .frame(width: Design.Layout.headerButtonSize, height: Design.Layout.headerButtonSize)
            }
        }
    }

    @ViewBuilder
    private var noteRelatedActionButtons: some View {
        // Sort picker and create button have moved into the NoteListView grid
        goToTrashButton

        goToSettingsButton
    }

    private var goToTrashButton: some View {
        Button { currentViewInApp = .trash } label: {
            headerIcon("trash")
        }
    }

    private var goToSettingsButton: some View {
        Button { currentViewInApp = .settings } label: {
            headerIcon("gearshape")
        }
    }

    /// Secondary icon sized for the top navigation bar. Only the SF Symbol name varies.
    private func headerIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: Design.FontSize.toolIcon))
            .foregroundStyle(.secondary)
            .frame(width: Design.Layout.headerButtonSize, height: Design.Layout.headerButtonSize)
    }

    /// Whether the current view shows folders (only at root level).
    private var isShowingFolders: Bool {
        currentViewInApp == .allNotes
    }

    // MARK: - Create / Import Helpers

    private func createNewNote() {
        let newNote = Note()
        // If we are currently inside a folder, the new note should be put there.
        if let folder = currentViewInApp.folder {
            newNote.folder = folder
        }
        modelContext.insert(newNote)
        noteNavigationStack.append(newNote.id)
    }

    private func importPDF(from url: URL) {
        let newNote = Note()
        // Use the file name (without extension) as the note title.
        newNote.title = url.deletingPathExtension().lastPathComponent
        if let folder = currentViewInApp.folder {
            newNote.folder = folder
        }
        modelContext.insert(newNote)
        PDFService.importPDF(url: url, into: newNote, modelContext: modelContext)
        noteNavigationStack.append(newNote.id)
    }

    private func importImage(_ image: UIImage) {
        let newNote = Note()
        newNote.title = "Imported Image"
        if let folder = currentViewInApp.folder {
            newNote.folder = folder
        }
        modelContext.insert(newNote)
        PDFService.importImage(image, into: newNote, modelContext: modelContext)
        noteNavigationStack.append(newNote.id)
    }

    private var titleForCurrentView: String {
        switch currentViewInApp {
        case .trash: return "Trash"
        case .settings: return "Settings"
        case .allNotes: return "All Notes"
        case let .folder(folder): return folder.name
        }
    }
}
