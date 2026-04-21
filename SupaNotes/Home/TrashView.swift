import SwiftData
import SwiftUI

struct TrashView: View {
    @Environment(\.modelContext) private var modelContext

    /// A list of all notes that have been moved to the trash (isDeleted == true)
    @Query(
        filter: #Predicate<Note> { $0.isDeleted == true },
        sort: \Note.deletedAt,
        order: .reverse
    ) private var notesCurrentlyInTrash: [Note]

    /// Tracks if the user is currently picking multiple notes to delete or restore
    @State private var userIsCurrentlySelectingNotes = false

    /// A set of note IDs that the user has selected while in selection mode
    @State private var notesSelectedForAction: Set<UUID> = []

    @State private var showEmptyTrashConfirmationAlert = false
    @State private var showDeleteSelectedConfirmationAlert = false

    var body: some View {
        VStack(spacing: 0) {
            // The bar at the top with "Select" and "Empty Trash" buttons
            trashHeaderToolbar

            Divider()

            if notesCurrentlyInTrash.isEmpty {
                emptyTrashPlaceholderView
            } else {
                listOfTrashedNotes
            }
        }
        .alert("Empty Trash?", isPresented: $showEmptyTrashConfirmationAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Empty Trash", role: .destructive) {
                permanentlyDeleteAllNotesInTrash()
            }
        } message: {
            let noteCount = notesCurrentlyInTrash.count
            Text("This will permanently delete all \(noteCount) " + (noteCount == 1 ? "note" : "notes") + ". This action cannot be undone.")
        }
        .alert(notesSelectedForAction.count == 1 ? "Delete 1 note?" : "Delete \(notesSelectedForAction.count) notes?", isPresented: $showDeleteSelectedConfirmationAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                permanentlyDeleteSelectedNotes()
            }
        } message: {
            Text("This will permanently delete the selected notes. This action cannot be undone.")
        }
    }

    // MARK: - Helper Methods (The "Logic")

    /// Deletes every single note that is currently in the trash
    private func permanentlyDeleteAllNotesInTrash() {
        for note in notesCurrentlyInTrash {
            modelContext.delete(note)
        }
    }

    /// Deletes only the notes that the user has checked off
    private func permanentlyDeleteSelectedNotes() {
        for note in notesCurrentlyInTrash where notesSelectedForAction.contains(note.id) {
            modelContext.delete(note)
        }
        stopSelectingNotes()
    }

    /// Restores the selected notes back to their original folders
    private func restoreSelectedNotesToOriginalLocation() {
        for note in notesCurrentlyInTrash where notesSelectedForAction.contains(note.id) {
            note.restore()
        }
        stopSelectingNotes()
    }

    /// Turns off selection mode and clears the checkmarks
    private func stopSelectingNotes() {
        notesSelectedForAction.removeAll()
        userIsCurrentlySelectingNotes = false
    }

    /// Checks or unchecks a specific note
    private func toggleCheckmarkForNote(_ noteID: UUID) {
        if notesSelectedForAction.contains(noteID) {
            notesSelectedForAction.remove(noteID)
        } else {
            notesSelectedForAction.insert(noteID)
        }
    }

    // MARK: - Subviews (The "UI Parts")

    private var emptyTrashPlaceholderView: some View {
        ContentUnavailableView(
            "Trash is Empty",
            systemImage: "trash",
            description: Text("Deleted notes will appear here.")
        )
    }

    private var listOfTrashedNotes: some View {
        List {
            ForEach(notesCurrentlyInTrash) { note in
                trashedNoteRow(for: note)
            }
        }
        .listStyle(.plain)
        .overlay(selectionModeBottomActionBar, alignment: .bottom)
    }

    private func trashedNoteRow(for note: Note) -> some View {
        HStack {
            NoteRowView(
                title: note.title,
                subtitle: note.deletedAt.map { "Deleted \($0.formatted(.relative(presentation: .named)))" } ?? ""
            )
            Spacer()

            // If we are selecting, show a circle or a checkmark
            if userIsCurrentlySelectingNotes {
                selectionIndicatorIcon(isNoteSelected: notesSelectedForAction.contains(note.id))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if userIsCurrentlySelectingNotes {
                toggleCheckmarkForNote(note.id)
            }
        }
        .swipeActions(edge: .trailing) {
            // Only allow swipe-to-delete if we aren't already in bulk selection mode
            if !userIsCurrentlySelectingNotes {
                Button("Delete", role: .destructive) {
                    modelContext.delete(note)
                }
            }
        }
        .swipeActions(edge: .leading) {
            if !userIsCurrentlySelectingNotes {
                Button("Restore") {
                    note.restore()
                }
                .tint(.green)
            }
        }
    }

    private func selectionIndicatorIcon(isNoteSelected: Bool) -> some View {
        Image(systemName: isNoteSelected ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(isNoteSelected ? .blue : .secondary)
    }

    private var trashHeaderToolbar: some View {
        HStack {
            if userIsCurrentlySelectingNotes {
                // When selecting: show "Done" and how many are picked
                Button("Done") {
                    stopSelectingNotes()
                }
                Spacer()
                Text("\(notesSelectedForAction.count) selected")
                    .foregroundStyle(.secondary)
                Spacer()
            } else if !notesCurrentlyInTrash.isEmpty {
                // Normally: show "Select" and "Empty Trash" buttons
                Spacer()
                Button("Select") {
                    userIsCurrentlySelectingNotes = true
                }

                Button {
                    showEmptyTrashConfirmationAlert = true
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
    private var selectionModeBottomActionBar: some View {
        if userIsCurrentlySelectingNotes {
            HStack(spacing: 16) {
                Button {
                    restoreSelectedNotesToOriginalLocation()
                } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                }
                .disabled(notesSelectedForAction.isEmpty)

                Spacer()

                Button(role: .destructive) {
                    if !notesSelectedForAction.isEmpty {
                        showDeleteSelectedConfirmationAlert = true
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(notesSelectedForAction.isEmpty)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
    }
}
