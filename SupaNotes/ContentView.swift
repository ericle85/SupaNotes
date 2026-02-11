import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            NoteListView()
                .navigationTitle("Your Notes")
                .navigationDestination(for: Note.self) { note in
                    NoteEditorView(note: note)
                }
        } detail: {
            ContentUnavailableView(
                "Select a Note",
                systemImage: "pencil.and.scribble",
                description: Text("Choose a note from the sidebar or create a new one.")
            )
        }
        .navigationSplitViewStyle(.balanced)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Note.self, inMemory: true)
}
