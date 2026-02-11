import SwiftUI
import SwiftData

@main
struct SupaNotesApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: Note.self)
    }
}
