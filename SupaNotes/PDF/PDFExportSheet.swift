import SwiftUI

struct PDFExportSheet: View {
    let note: Note
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<UUID> = []
    @State private var exportURL: URL?

    private let columns = [GridItem(.adaptive(minimum: 130), spacing: 12)]

    // True when every page is currently selected
    private var allSelected: Bool { selection.count == note.sortedPages.count }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Toggle between select-all and deselect-all
                HStack {
                    Button(allSelected ? "Deselect All" : "Select All") {
                        if allSelected {
                            selection.removeAll()
                        } else {
                            selection = Set(note.sortedPages.map(\.id))
                        }
                    }
                    .font(.subheadline)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Array(note.sortedPages.enumerated()), id: \.element.id) { idx, page in
                            thumbnailCell(page: page, index: idx)
                        }
                    }
                    .padding()
                }

                Button {
                    exportAndShare()
                } label: {
                    Label(buttonTitle, systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canExport ? Color.accentColor : Color.gray)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!canExport)
                .padding()
            }
            .navigationTitle("Export PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            // Pre-select all pages on appear
            .onAppear { selection = Set(note.sortedPages.map(\.id)) }
            .sheet(item: $exportURL) { url in
                ShareSheet(items: [url])
            }
        }
    }

    @ViewBuilder
    private func thumbnailCell(page: Page, index: Int) -> some View {
        let selected = selection.contains(page.id)
        Button {
            // Toggle this page's selection
            if selected { selection.remove(page.id) } else { selection.insert(page.id) }
        } label: {
            VStack(spacing: 4) {
                PageThumbnail(page: page)
                    .frame(width: 130, height: 168)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22))
                            .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                            .background(Circle().fill(.white).padding(2))
                            .padding(6)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(selected ? Color.accentColor : Color.black.opacity(0.15), lineWidth: selected ? 3 : 1)
                    )
                Text("Page \(index + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var buttonTitle: String {
        "Export \(selection.count) Page\(selection.count == 1 ? "" : "s")"
    }

    private var canExport: Bool {
        !selection.isEmpty
    }

    private func exportAndShare() {
        // Pass nil when all pages selected (export full note), otherwise filter
        let pages: [Page]? = allSelected ? nil : note.sortedPages.filter { selection.contains($0.id) }
        guard let data = PDFService.exportNote(note, pages: pages) else { return }
        // Sanitize title to prevent path traversal or invalid filenames.
        let safeTitle = note.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "..", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeTitle).pdf")
        do {
            try data.write(to: url)
            exportURL = url
        } catch {
            assertionFailure("PDF write failed: \(error)")
        }
    }
}

private struct PageThumbnail: View {
    let page: Page
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color(uiColor: page.template.backgroundColor))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ProgressView()
            }
        }
        .task(id: page.id) {
            // Render off main thread to avoid UI freeze with many pages.
            let img = await Task.detached { PDFService.thumbnail(for: page, width: 260) }.value
            self.image = img
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String {
        absoluteString
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
