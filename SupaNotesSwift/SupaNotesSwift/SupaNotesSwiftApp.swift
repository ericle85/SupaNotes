import SwiftUI

@main
struct SupaNotesSwiftApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    try? await AutocompleteModelCache.shared.prepare()
                }
        }
    }
}
