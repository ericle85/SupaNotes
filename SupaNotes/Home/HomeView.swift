import SwiftUI
import SwiftData

enum NoteSortOrder: String, CaseIterable {
    case name = "Name"
    case lastEdited = "Last Edited"
    case dateCreated = "Date Created"
}

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var isSidebarVisible = true
    @State private var selectedFolder: Folder?
    @State private var showingAllNotes = true
    @State private var showingTrash = false
    @State private var showingSettings = false
    @State private var sortOrder: NoteSortOrder = .lastEdited
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            HStack(spacing: 0) {
                // Sidebar
                if isSidebarVisible {
                    FolderSidebarView(
                        selectedFolder: $selectedFolder,
                        showingAllNotes: $showingAllNotes,
                        showingTrash: $showingTrash,
                        showingSettings: $showingSettings
                    )
                    .frame(width: 260)
                    .transition(.move(edge: .leading))
                }

                // Main content
                VStack(spacing: 0) {
                    // Header
                    headerView
                    Divider()

                    // Content
                    if showingTrash {
                        TrashView()
                    } else if showingSettings {
                        SettingsView()
                    } else {
                        NoteListView(
                            folder: showingAllNotes ? nil : selectedFolder,
                            sortOrder: sortOrder,
                            onOpenNote: { noteID in
                                navigationPath.append(noteID)
                            }
                        )
                    }
                }
            }
            .background(Color("PaperBackground"))
            .navigationBarHidden(true)
            .navigationDestination(for: UUID.self) { noteID in
                NoteEditorView(noteID: noteID)
            }
        }
    }

    @ViewBuilder
    private var headerView: some View {
        HStack(spacing: 12) {
            // Sidebar toggle
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isSidebarVisible.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 18))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
            }

            // Title
            Text(headerTitle)
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            if !showingTrash && !showingSettings {
                // Sort menu
                Menu {
                    ForEach(NoteSortOrder.allCases, id: \.self) { order in
                        Button {
                            sortOrder = order
                        } label: {
                            HStack {
                                Text(order.rawValue)
                                if sortOrder == order {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                }

                // New folder
                Button {
                    let folder = Folder()
                    modelContext.insert(folder)
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                }

                // New note
                Button {
                    let note = Note()
                    if !showingAllNotes, let folder = selectedFolder {
                        note.folder = folder
                    }
                    modelContext.insert(note)
                    navigationPath.append(note.id)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.accentColor)
                        )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var headerTitle: String {
        if showingTrash { return "Trash" }
        if showingSettings { return "Settings" }
        if showingAllNotes { return "All Notes" }
        return selectedFolder?.name ?? "Notes"
    }
}
