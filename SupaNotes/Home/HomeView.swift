import SwiftData
import SwiftUI

enum NoteSortOrder: String, CaseIterable {
    case name = "Name"
    case lastEdited = "Last Edited"
    case dateCreated = "Date Created"
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
    }

    @ViewBuilder
    private var mainContentArea: some View {
        switch currentViewInApp {
        case .trash:
            TrashView()
        case .settings:
            SettingsView()
        case .allNotes:
            NoteListView(
                folder: nil,
                sortOrder: selectedNoteSortOrder,
                onOpenNote: { noteID in noteNavigationStack.append(noteID) },
                onOpenFolder: { folder in currentViewInApp = .folder(folder) }
            )
        case let .folder(folder):
            NoteListView(
                folder: folder,
                sortOrder: selectedNoteSortOrder,
                onOpenNote: { noteID in noteNavigationStack.append(noteID) },
                onOpenFolder: { folder in currentViewInApp = .folder(folder) }
            )
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
        sortOrderMenuButton

        createNewFolderButton

        goToTrashButton

        goToSettingsButton

        createNewNoteButton
    }

    private var sortOrderMenuButton: some View {
        Menu {
            ForEach(NoteSortOrder.allCases, id: \.self) { order in
                Button {
                    selectedNoteSortOrder = order
                } label: {
                    HStack {
                        Text(order.rawValue)
                        if selectedNoteSortOrder == order {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            headerIcon("arrow.up.arrow.down")
        }
    }

    private var createNewFolderButton: some View {
        Button {
            let newFolder = Folder()
            modelContext.insert(newFolder)
        } label: {
            headerIcon("folder.badge.plus")
        }
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

    private var createNewNoteButton: some View {
        Button {
            let newNote = Note()
            // If we are currently inside a folder, the new note should be put there
            if let folder = currentViewInApp.folder {
                newNote.folder = folder
            }
            modelContext.insert(newNote)
            noteNavigationStack.append(newNote.id)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: Design.FontSize.headerIcon, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Design.Layout.headerButtonSize, height: Design.Layout.headerButtonSize)
                .background(
                    RoundedRectangle(cornerRadius: Design.CornerRadius.small)
                        .fill(Color.accentColor)
                )
        }
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
