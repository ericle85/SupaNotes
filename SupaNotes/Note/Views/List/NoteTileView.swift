import SwiftUI

/// A single tile in the note grid — shows a page thumbnail, a title menu, and the last-edited date.
/// The thumbnail is generated from the first page of the note using PageRenderer.
struct NoteTileView: View {
    let note: Note
    let onOpen: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    // Thumbnail rendered from the note's first page
    @State private var thumbnail: UIImage?

    // Width used when rendering the thumbnail bitmap (points, not pixels)
    private let renderWidth: CGFloat = 200

    // Page aspect ratio so every tile has the same proportions
    private let pageAspect = PageConstants.pageWidth / PageConstants.pageHeight

    var body: some View {
        VStack(spacing: 6) {
            // Tappable thumbnail that opens the note
            thumbnailButton

            // Title with a dropdown menu for rename / delete
            titleMenu

            // Last-edited date
            dateLabel
        }
        // Re-render the thumbnail whenever the note changes
        .task(id: note.updatedAt) {
            renderThumbnail()
        }
    }

    // MARK: - Subviews

    /// The large tappable thumbnail image area
    private var thumbnailButton: some View {
        Button(action: onOpen) {
            thumbnailContent
                .aspectRatio(pageAspect, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.small))
                .overlay(
                    // Thin border to separate the tile from the background
                    RoundedRectangle(cornerRadius: Design.CornerRadius.small)
                        .stroke(Color(.systemGray4), lineWidth: 0.5)
                )
                .shadow(
                    color: .black.opacity(Design.Shadow.page.opacity),
                    radius: Design.Shadow.page.radius,
                    x: Design.Shadow.page.x,
                    y: Design.Shadow.page.y
                )
        }
        .buttonStyle(.plain)
    }

    /// Shows the rendered thumbnail or a gray placeholder while loading
    @ViewBuilder
    private var thumbnailContent: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            // Placeholder while the thumbnail is being generated
            Rectangle()
                .fill(Color(.systemGray6))
        }
    }

    /// Dropdown menu attached to the note title — mirrors the old context menu actions
    private var titleMenu: some View {
        Menu {
            Button("Rename", action: onRename)
            Button("Move to Trash", role: .destructive, action: onDelete)
        } label: {
            HStack(spacing: 2) {
                Text(note.title)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
            }
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(Color.accentColor)
        }
    }

    /// Abbreviated date + time shown under the title
    private var dateLabel: some View {
        Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    // MARK: - Thumbnail Generation

    /// Renders a small bitmap of the note's first page via PageRenderer
    // ALL THUMBNAILS ARE JUST 1st PAGE
    private func renderThumbnail() {
        guard let page = note.sortedPages.first else {
            thumbnail = nil
            return
        }
        thumbnail = PageRenderer.thumbnail(for: page, width: renderWidth)
    }
}
