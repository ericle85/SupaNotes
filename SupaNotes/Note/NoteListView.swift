import SwiftUI
import SwiftData

struct  NoteListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @Binding var selectedNoteID: UUID?

    var body: some View {
        List(selection: $selectedNoteID) {
            ForEach(notes) { note in
                NavigationLink(value: note.id) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.title)
                            .font(.headline)
                    }
                    .padding(.vertical, 4)
                }
            }
            .onDelete(perform: deleteNotes)
        }
        .overlay {
            if notes.isEmpty {
                ContentUnavailableView(
                    "No Notes",
                    systemImage: "note.text",
                    description: Text("Tap + to create a new note.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: addNote) {
                    Label("New Note", systemImage: "plus")
                }
            }
        }
    }

    private func addNote() {
        let note = Note()
        modelContext.insert(note)
        selectedNoteID = note.id
    }

    private func deleteNotes(at offsets: IndexSet) {
        for index in offsets {
            let note = notes[index]
            if selectedNoteID == note.id {
                selectedNoteID = nil
            }
            modelContext.delete(note)
        }
    }
}
