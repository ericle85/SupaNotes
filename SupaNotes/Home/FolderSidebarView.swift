import SwiftUI
import SwiftData

struct FolderSidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Folder.createdAt) private var folders: [Folder]
    @Query(filter: #Predicate<Note> { $0.isDeleted == true }) private var trashedNotes: [Note]
    @Binding var selectedFolder: Folder?
    @Binding var showingAllNotes: Bool
    @Binding var showingTrash: Bool
    @Binding var showingSettings: Bool

    @State private var editingFolder: Folder?
    @State private var editingName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Home (All Notes)
            sidebarButton(
                icon: "house",
                label: "All Notes",
                isSelected: showingAllNotes && !showingTrash && !showingSettings
            ) {
                showingAllNotes = true
                showingTrash = false
                showingSettings = false
                selectedFolder = nil
            }

            Divider()
                .padding(.vertical, 8)

            // Folders section
            Text("FOLDERS")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(folders) { folder in
                        folderRow(folder)
                    }
                }
            }

            Spacer()

            Divider()

            // Trash
            sidebarButton(
                icon: "trash",
                label: "Trash",
                isSelected: showingTrash,
                badge: trashedNotes.count > 0 ? trashedNotes.count : nil
            ) {
                showingTrash = true
                showingSettings = false
                showingAllNotes = false
            }

            // Settings
            sidebarButton(
                icon: "gearshape",
                label: "Settings",
                isSelected: showingSettings
            ) {
                showingSettings = true
                showingTrash = false
                showingAllNotes = false
            }
        }
        .padding(.vertical, 8)
        .background(Color("SidebarBackground"))
    }

    @ViewBuilder
    private func sidebarButton(icon: String, label: String, isSelected: Bool, badge: Int? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .frame(width: 24)
                Text(label)
                    .font(.body)
                Spacer()
                if let badge {
                    Text("\(badge)")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.secondary))
                }
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.primary.opacity(0.08) : .clear)
                    .padding(.horizontal, 8)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func folderRow(_ folder: Folder) -> some View {
        let isSelected = !showingAllNotes && !showingTrash && !showingSettings && selectedFolder?.id == folder.id

        if editingFolder?.id == folder.id {
            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .font(.system(size: 16))
                    .frame(width: 24)
                TextField("Folder name", text: $editingName)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .onSubmit {
                        folder.name = editingName
                        editingFolder = nil
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
        } else {
            sidebarButton(
                icon: "folder",
                label: folder.name,
                isSelected: isSelected
            ) {
                selectedFolder = folder
                showingAllNotes = false
                showingTrash = false
                showingSettings = false
            }
            .contextMenu {
                Button("Rename") {
                    editingName = folder.name
                    editingFolder = folder
                }
                Button("Delete", role: .destructive) {
                    modelContext.delete(folder)
                }
            }
        }
    }
}
