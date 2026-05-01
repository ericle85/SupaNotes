import SwiftData
import SwiftUI

@main
struct SupaNotesApp: App {
    @State private var toolbarState = ToolbarState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(toolbarState)
        }
        .modelContainer(for: [Note.self, Page.self, Folder.self])
    }
}
