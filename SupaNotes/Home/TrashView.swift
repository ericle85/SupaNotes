import SwiftUI
import SwiftData

struct TrashView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<Note> { $0.isDeleted == true },
        sort: \Note.deletedAt,
        order: .reverse
    ) private var trashedNotes: [Note]

    @State private var isSelectionMode = false
    @State private var selectedNotes: Set<UUID> = []
    @State private var showEmptyTrashAlert = false
    @State private var showDeleteSelectedAlert = false

    var body: some View {
        VStack(spacing: 0) {
            headerToolbar
            Divider()

            if trashedNotes.isEmpty {
                ContentUnavailableView(
                    "Trash is Empty",
                    systemImage: "trash",
                    description: Text("Deleted notes will appear here.")
                )
            } else {
                List {
                    ForEach(trashedNotes) { note in
                        HStack {
                            NoteRowView(
                                title: note.title,
                                subtitle: note.deletedAt.map { "Deleted \($0.formatted(.relative(presentation: .named)))" } ?? ""
                            )
                            Spacer()

                            // Selection indicator
                            if isSelectionMode {
                                Image(systemName: selectedNotes.contains(note.id)
                                    ? "checkmark.circle.fill"
                                    : "circle")
                                    .foregroundStyle(selectedNotes.contains(note.id)
                                        ? .blue
                                        : .secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isSelectionMode {
                                toggleSelection(note.id)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            if !isSelectionMode {
                                Button("Delete", role: .destructive) {
                                    modelContext.delete(note)
                                }
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if !isSelectionMode {
                                Button("Restore") {
                                    note.restore()
                                }
                                .tint(.green)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .overlay(selectionActionBar, alignment: .bottom)
            }
        }
        .alert("Empty Trash?", isPresented: $showEmptyTrashAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Empty Trash", role: .destructive) {
                emptyTrash()
            }
        } message: {
            Text("This will permanently delete all \(trashedNotes.count) " + (trashedNotes.count == 1 ? "note" : "notes") + ". This action cannot be undone.")
        }
        .alert(selectedNotes.count == 1 ? "Delete 1 note?" : "Delete \(selectedNotes.count) notes?", isPresented: $showDeleteSelectedAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteSelectedNotes()
            }
        } message: {
            Text("This will permanently delete the selected notes. This action cannot be undone.")
        }
    }

    // MARK: - Helper Methods

    private func emptyTrash() {
        for note in trashedNotes {
            modelContext.delete(note)
        }
    }

    private func deleteSelectedNotes() {
        for note in trashedNotes where selectedNotes.contains(note.id) {
            modelContext.delete(note)
        }
        exitSelectionMode()
    }

    private func restoreSelectedNotes() {
        for note in trashedNotes where selectedNotes.contains(note.id) {
            note.restore()
        }
        exitSelectionMode()
    }

    private func exitSelectionMode() {
        selectedNotes.removeAll()
        isSelectionMode = false
    }

    private func toggleSelection(_ noteID: UUID) {
        if selectedNotes.contains(noteID) {
            selectedNotes.remove(noteID)
        } else {
            selectedNotes.insert(noteID)
        }
    }

    // MARK: - Views

    @ViewBuilder
    private var headerToolbar: some View {
        HStack {
            if isSelectionMode {
                // Selection mode: Cancel | X selected | Done
                Button("Cancel") {
                    exitSelectionMode()
                }
                Spacer()
                Text("\(selectedNotes.count) selected")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") {
                    exitSelectionMode()
                }
            } else if !trashedNotes.isEmpty {
                // Normal mode: Select | Empty Trash buttons
                Spacer()
                Button("Select") {
                    isSelectionMode = true
                }

                Button {
                    showEmptyTrashAlert = true
                } label: {
                    Image(systemName: "trash.slash")
                        .font(.system(size: Design.FontSize.toolIcon))
                        .foregroundStyle(.red)
                        .frame(width: Design.Layout.headerButtonSize,
                               height: Design.Layout.headerButtonSize)
                }
            }
        }
        .padding(.horizontal, Design.Spacing.headerHorizontal)
        .padding(.vertical, Design.Spacing.headerVertical)
    }

    @ViewBuilder
    private var selectionActionBar: some View {
        if isSelectionMode {
            HStack(spacing: 16) {
                Button {
                    restoreSelectedNotes()
                } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                }
                .disabled(selectedNotes.isEmpty)

                Spacer()

                Button(role: .destructive) {
                    if !selectedNotes.isEmpty {
                        showDeleteSelectedAlert = true
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selectedNotes.isEmpty)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
    }
}
