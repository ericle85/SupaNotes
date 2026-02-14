import SwiftUI
import SwiftData

struct TrashView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<Note> { $0.isDeleted == true },
        sort: \Note.deletedAt,
        order: .reverse
    ) private var trashedNotes: [Note]

    var body: some View {
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
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Delete", role: .destructive) {
                            modelContext.delete(note)
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button("Restore") {
                            note.restore()
                        }
                        .tint(.green)
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}
