import SwiftData
import SwiftUI

struct NoteTabsBar: View {
    @Environment(TabsState.self) private var tabs
    @Query private var notes: [Note]

    private var openNotes: [Note] {
        let map = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        return tabs.openTabIDs.compactMap { map[$0] }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(openNotes, id: \.id) { note in
                    tab(for: note)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func tab(for note: Note) -> some View {
        let isActive = tabs.activeTabID == note.id
        HStack(spacing: 6) {
            Button {
                tabs.activate(note.id)
            } label: {
                Text(note.title)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundStyle(isActive ? Color.primary : Color.secondary)
            }
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
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
        )
    }
}
