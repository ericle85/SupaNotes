import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        HomeView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Note.self, Page.self, Folder.self], inMemory: true)
        .environment(ToolbarState())
}
