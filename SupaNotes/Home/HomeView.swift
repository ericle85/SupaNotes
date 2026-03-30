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
    @State private var destination: SidebarDestination = .allNotes
    @State private var sortOrder: NoteSortOrder = .lastEdited
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            HStack(spacing: 0) {
                if isSidebarVisible {
                    FolderSidebarView(destination: $destination)
                        .frame(width: Design.Layout.sidebarWidth)
                        .transition(.move(edge: .leading))
                }

                VStack(spacing: 0) {
                    headerView
                    Divider()

                    switch destination {
                    case .trash:
                        TrashView()
                    case .settings:
                        SettingsView()
                    case .hwrDemo:
                        HWRDemoView()
                    case .visionBenchmark:
                        VisionBenchmarkView()
                    case .allNotes:
                        NoteListView(
                            folder: nil,
                            sortOrder: sortOrder,
                            onOpenNote: { navigationPath.append($0) }
                        )
                    case .folder(let folder):
                        NoteListView(
                            folder: folder,
                            sortOrder: sortOrder,
                            onOpenNote: { navigationPath.append($0) }
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
            Button {
                withAnimation(.easeInOut(duration: Design.Animation.sidebarDuration)) {
                    isSidebarVisible.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: Design.FontSize.headerIcon))
                    .foregroundStyle(.primary)
                    .frame(width: Design.Layout.headerButtonSize, height: Design.Layout.headerButtonSize)
            }

            Text(headerTitle)
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            if destination.showsNoteActions {
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
                        .font(.system(size: Design.FontSize.toolIcon))
                        .foregroundStyle(.secondary)
                        .frame(width: Design.Layout.headerButtonSize, height: Design.Layout.headerButtonSize)
                }

                Button {
                    let folder = Folder()
                    modelContext.insert(folder)
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: Design.FontSize.toolIcon))
                        .foregroundStyle(.secondary)
                        .frame(width: Design.Layout.headerButtonSize, height: Design.Layout.headerButtonSize)
                }

                Button {
                    let note = Note()
                    if let folder = destination.folder {
                        note.folder = folder
                    }
                    modelContext.insert(note)
                    navigationPath.append(note.id)
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
        }
        .padding(.horizontal, Design.Spacing.headerHorizontal)
        .padding(.vertical, Design.Spacing.headerVertical)
    }

    private var headerTitle: String {
        switch destination {
        case .trash: return "Trash"
        case .settings: return "Settings"
        case .hwrDemo: return "HWR Demo"
        case .visionBenchmark: return "Vision Benchmark"
        case .allNotes: return "All Notes"
        case .folder(let folder): return folder.name
        }
    }
}
