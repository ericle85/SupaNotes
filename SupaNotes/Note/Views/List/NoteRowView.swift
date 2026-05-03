import SwiftUI

/// A single row in a note list — shows a bold title and a smaller subtitle below it.
/// Used in NoteListView (the main note browser) and TrashView (deleted notes).
/// The caller is responsible for passing the right strings; this view just handles the layout.
struct NoteRowView: View {
    /// The main text shown in large bold — typically the note's title.
    let title: String
    /// The smaller text shown below the title — typically a date or preview snippet.
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Title in medium weight so it stands out as the primary piece of info.
            Text(title)
                .font(.body)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
            // Subtitle in a smaller, dimmer style so it is visible but secondary.
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
