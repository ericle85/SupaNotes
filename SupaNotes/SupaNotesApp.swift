import SwiftUI
import SwiftData

@main
struct SupaNotesApp: App {
    @State private var toolbarState = ToolbarState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(toolbarState)
        }
        .modelContainer(for: [Note.self, NoteImage.self, NoteTextBox.self])
    }
}
