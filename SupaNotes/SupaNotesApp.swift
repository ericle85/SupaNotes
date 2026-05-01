import SwiftData
import SwiftUI

@main
struct SupaNotesApp: App {
    @State private var toolbarState = ToolbarState()

    // True when the app was launched by an XCUITest with -uitest-seed-tabs.
    // In that mode we use an in-memory store and pre-create two known notes
    // so tab-switching tests are deterministic and never pollute disk state.
    private static let isUITestTabSeed: Bool =
        ProcessInfo.processInfo.arguments.contains("-uitest-seed-tabs")

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(toolbarState)
        }
        .modelContainer(SupaNotesApp.makeContainer())
    }

    // Build either the normal disk-backed container or an in-memory one
    // pre-seeded with two distinct notes for tab-switching UI tests.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([Note.self, Page.self, Folder.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isUITestTabSeed
        )
        let container = try! ModelContainer(for: schema, configurations: [config])
        if isUITestTabSeed {
            seedTabFixtures(into: container)
        }
        return container
    }

    // Insert two notes with unique, test-known titles so the UI test can
    // identify each tab and assert which canvas is currently rendered.
    @MainActor
    private static func seedTabFixtures(into container: ModelContainer) {
        let context = container.mainContext
        let a = Note(title: "TabUITestA")
        let b = Note(title: "TabUITestB")
        context.insert(a)
        context.insert(b)
        try? context.save()
        // Wipe any stale tab IDs persisted by a previous test run.
        UserDefaults.standard.removeObject(forKey: "supanotes.openTabs")
    }
}
