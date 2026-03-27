import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var showOverlayPrototype = false

    var body: some View {
        HomeView()
            .overlay(alignment: .topTrailing) {
                Button("Prototype") { showOverlayPrototype = true }
                    .buttonStyle(.bordered)
                    .padding(8)
            }
            .sheet(isPresented: $showOverlayPrototype) {
                NavigationStack {
                    OverlayAccuracyView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { showOverlayPrototype = false }
                            }
                        }
                }
            }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Note.self, Page.self, Folder.self], inMemory: true)
        .environment(ToolbarState())
}
