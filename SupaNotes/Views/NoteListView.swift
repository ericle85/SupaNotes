import SwiftUI
import SwiftData

struct NoteListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]

    var body: some View {
        List {
            ForEach(notes) { note in
                NavigationLink(value: note) {
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
    }

    private func deleteNotes(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(notes[index])
        }
    }
}
