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
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.title)
                                .font(.body)
                                .fontWeight(.medium)
                            if let deletedAt = note.deletedAt {
                                Text("Deleted \(deletedAt, format: .relative(presentation: .named))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Delete", role: .destructive) {
                            modelContext.delete(note)
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button("Restore") {
                            note.isDeleted = false
                            note.deletedAt = nil
                        }
                        .tint(.green)
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}
