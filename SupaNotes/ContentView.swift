import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedNoteID: UUID?

    var body: some View {
        NavigationSplitView {
            NoteListView(selectedNoteID: $selectedNoteID)
                .navigationTitle("Your Notes")
        } detail: {
            if let selectedNoteID {
                NoteEditorView(noteID: selectedNoteID)
                    .id(selectedNoteID)
            } else {
                ContentUnavailableView(
                    "Select a Note",
                    systemImage: "pencil.and.scribble",
                    description: Text("Choose a note from the sidebar or create a new one.")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Note.self, inMemory: true)
        .environment(ToolbarState())
}
