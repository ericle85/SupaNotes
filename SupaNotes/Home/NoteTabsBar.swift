import SwiftData
import SwiftUI

// MARK: - Note Tabs Bar

struct NoteTabsBar: View {
    @Environment(TabsState.self) private var tabs // The tabs state manager.
    @Query private var notes: [Note] // All notes from the database.

    private var openNotes: [Note] {
        // Build a lookup map from note ID to note for efficient access.
        let map = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        // Return notes that match the open tab IDs, in order.
        return tabs.openTabIDs.compactMap { map[$0] }
    }

    /// SwiftUI view body.
    var body: some View {
        // Horizontal scroll view for tabs.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                // Render a tab for each open note.
                ForEach(openNotes, id: \.id) { note in
                    tab(for: note)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        // Use ultra-thin material for a frosted glass effect.
        .background(.ultraThinMaterial)
    }

    /// Build the UI for a single tab.
    @ViewBuilder
    private func tab(for note: Note) -> some View {
        // Check if this tab is the currently active one.
        let isActive = tabs.activeTabID == note.id
        HStack(spacing: 6) {
            // Tab title button - activates the tab when tapped. Uses a fixed
            // 32pt hit target so XCUITest taps (and fingers) reliably land on
            // the button instead of slipping through to the underlying scroll view.
            Button {
                tabs.activate(note.id)
            } label: {
                Text(note.title)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundStyle(isActive ? Color.primary : Color.secondary) // Use primary color for active tab, secondary for inactive.
                    .frame(minHeight: 32)
                    .contentShape(Rectangle())
            }
            // Stable identifier for XCUITest — title is shown to users; identifier is for tests.
            .accessibilityIdentifier("tab.\(note.title)")
            // Close button - removes the tab when tapped.
            Button {
                tabs.close(noteID: note.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            // Add a subtle background for the active tab.
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? Color.accentColor.opacity(0.15) : Color.clear) // Use accent color with 15% opacity for active tab, clear for inactive.
        )
    }
}
