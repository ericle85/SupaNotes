import SwiftUI

struct PDFExportSheet: View {
    let note: Note
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<UUID> = []
    @State private var mode: Mode = .all
    @State private var exportURL: URL?

    enum Mode: String, CaseIterable { case all = "All Pages", selected = "Select Pages" }

    private let columns = [GridItem(.adaptive(minimum: 130), spacing: 12)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases, id: \.rawValue) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

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
            .sheet(item: $exportURL) { url in
                ShareSheet(items: [url])
            }
        }
    }

    @ViewBuilder
    private func thumbnailCell(page: Page, index: Int) -> some View {
        let selected = selection.contains(page.id)
        let selectable = mode == .selected
        Button {
            guard selectable else { return }
            if selected { selection.remove(page.id) } else { selection.insert(page.id) }
        } label: {
            VStack(spacing: 4) {
                PageThumbnail(page: page)
                    .frame(width: 130, height: 168)
                    .overlay(alignment: .topTrailing) {
                        if selectable {
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                                .background(Circle().fill(.white).padding(2))
                                .padding(6)
                        }
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
        switch mode {
        case .all: return "Export \(note.pages.count) Page\(note.pages.count == 1 ? "" : "s")"
        case .selected: return "Export \(selection.count) Selected"
        }
    }

    private var canExport: Bool {
        mode == .all || !selection.isEmpty
    }

    private func exportAndShare() {
        let pages: [Page]? = mode == .all ? nil : note.sortedPages.filter { selection.contains($0.id) }
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
