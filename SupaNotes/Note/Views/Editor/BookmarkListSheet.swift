import SwiftUI

struct BookmarkListSheet: View {
    let note: Note
    let onTap: (Page) -> Void
    @Environment(\.dismiss) private var dismiss

    private var bookmarked: [Page] {
        note.sortedPages.filter { $0.isBookmarked }
    }

    var body: some View {
        NavigationStack {
            Group {
                if bookmarked.isEmpty {
                    ContentUnavailableView("No Bookmarks", systemImage: "bookmark", description: Text("Tap the bookmark icon on any page to add one."))
                } else {
                    List {
                        ForEach(Array(bookmarked.enumerated()), id: \.element.id) { _, page in
                            Button {
                                onTap(page)
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: "bookmark.fill").foregroundStyle(.orange)
                                    Text("Page \((note.sortedPages.firstIndex(where: { $0.id == page.id }) ?? 0) + 1)")
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Bookmarks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
