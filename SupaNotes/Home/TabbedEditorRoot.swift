import SwiftUI

struct TabbedEditorRoot: View {
    let initialID: UUID
    @Environment(TabsState.self) private var tabs
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            NoteTabsBar()
            Divider()
            Group {
                if let id = tabs.activeTabID {
                    NoteEditorView(noteID: id)
                        .id(id)
                } else {
                    ContentUnavailableView("No Open Tabs", systemImage: "doc.text")
                }
            }
        }
        .onAppear { tabs.open(noteID: initialID) }
        .onChange(of: tabs.openTabIDs) { _, new in
            if new.isEmpty { dismiss() }
        }
    }
}
