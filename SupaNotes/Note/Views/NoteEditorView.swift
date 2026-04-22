import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct NoteEditorView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(ToolbarState.self) private var toolbar
    @Environment(\.dismiss) private var dismiss
    @Query private var notes: [Note]
    /// The active page-specific undo stack from the multipage canvas.
    @State private var canvasUndoManager: UndoManager?
    /// The page the user is currently looking at in the vertical stack.
    @State private var currentPageIndex = 0

    private var note: Note? {
        notes.first
    }

    init(noteID: UUID) {
        _notes = Query(filter: #Predicate<Note> { note in
            note.id == noteID
        })
    }

    var body: some View {
        if let note {
            noteContent(note)
        } else {
            ContentUnavailableView("Note not found", systemImage: "exclamationmark.triangle")
        }
    }

    @ViewBuilder
    private func noteContent(_ note: Note) -> some View {
        @Bindable var toolbar = toolbar
        let pageManager = PageManager(modelContext: modelContext)

        ZStack {
            // Main multipage drawing surface with pinch-to-zoom + pull-to-add-page.
            PagedCanvasContainer(
                pages: Binding(
                    get: { note.sortedPages },
                    set: { _ in }
                ),
                toolbar: toolbar,
                onUndoManagerReady: { canvasUndoManager = $0 },
                onPencilDoubleTap: { toolbar.switchToPreviousTool() },
                onCurrentPageChanged: { currentPageIndex = $0 },
                addPage: { pageManager.addPage(to: note) },
                addPageAbove: { pageManager.addPageAbove(in: note) },
                onPageMutated: { note.updatedAt = .now }
            )
            .ignoresSafeArea()

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: Design.FontSize.headerIcon, weight: .semibold))
                            .foregroundStyle(.primary)
                            .floatingButton()
                    }
                    .padding(.leading, Design.Spacing.headerHorizontal)
                    .padding(.top, 12)
                    Spacer()
                    editorTopActions(note: note, pageManager: pageManager)
                        .padding(.trailing, Design.Spacing.headerHorizontal)
                        .padding(.top, 12)
                }
                Spacer()
            }

            // Floating tool palette (pen, eraser, colors, undo, etc).
            DrawingToolbar(toolbar: toolbar, undoManager: canvasUndoManager)

            VStack {
                Spacer()
                HStack {
                    // Bottom-left page number badge.
                    PageCounterView(currentPage: currentPageIndex, totalPages: note.pages.count)
                        .padding(.leading, Design.Spacing.pageCounterLeading)
                        .padding(.bottom, Design.Spacing.pageCounterBottom)
                    Spacer()
                }
            }
        }
        .navigationBarHidden(true)
        .onChange(of: toolbar.colorSelectedByUser) {
            toolbar.save(colorScheme: colorScheme)
        }
        .onChange(of: toolbar.currentlyActiveTool) { oldValue, newValue in
            if oldValue != newValue {
                toolbar.toolUsedPreviously = oldValue
            }
            toolbar.save(colorScheme: colorScheme)
        }
        .onChange(of: toolbar.toolbarIcons) {
            toolbar.save(colorScheme: colorScheme)
        }
        .sheet(isPresented: $showingBookmarks) {
            BookmarkListSheet(note: note, onTap: scrollToPage)
        }
        .sheet(isPresented: $showingExport) {
            PDFExportSheet(note: note)
        }
        .fileImporter(isPresented: $showingImport, allowedContentTypes: [.pdf]) { result in
            handleImport(result: result, note: note)
        }
    }

    @State private var showingBookmarks = false
    @State private var showingExport = false
    @State private var showingImport = false

    private var currentPage: Page? {
        guard let note else { return nil }
        let sorted = note.sortedPages
        guard sorted.indices.contains(currentPageIndex) else { return nil }
        return sorted[currentPageIndex]
    }

    private func editorTopActions(note: Note, pageManager _: PageManager) -> some View {
        HStack(spacing: 10) {
            Button {
                if let page = currentPage {
                    page.isBookmarked.toggle()
                    note.updatedAt = .now
                }
            } label: {
                Image(systemName: (currentPage?.isBookmarked ?? false) ? "bookmark.fill" : "bookmark")
                    .font(.system(size: Design.FontSize.headerIcon, weight: .semibold))
                    .foregroundStyle(.primary)
                    .floatingButton()
            }

            Button { showingBookmarks = true } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: Design.FontSize.headerIcon, weight: .semibold))
                    .foregroundStyle(.primary)
                    .floatingButton()
            }

            Menu {
                Button { showingImport = true } label: { Label("Import PDF", systemImage: "square.and.arrow.down") }
                Button {
                    flushDrawings()
                    showingExport = true
                } label: {
                    Label("Export PDF", systemImage: "square.and.arrow.up")
                }
                Button {
                    flushDrawings()
                    printNote(note)
                } label: {
                    Label("Print", systemImage: "printer")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: Design.FontSize.headerIcon, weight: .semibold))
                    .foregroundStyle(.primary)
                    .floatingButton()
            }
        }
    }

    private func scrollToPage(_ page: Page) {
        guard let note else { return }
        if let index = note.sortedPages.firstIndex(where: { $0.id == page.id }) {
            NotificationCenter.default.post(name: .scrollToPage, object: index)
        }
    }

    private func handleImport(result: Result<URL, Error>, note: Note) {
        guard case let .success(url) = result else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        PDFService.importPDF(url: url, into: note, modelContext: modelContext)
    }

    private func flushDrawings() {
        NotificationCenter.default.post(name: .flushDrawings, object: nil)
        try? modelContext.save()
    }

    private func printNote(_ note: Note) {
        guard let data = PDFService.exportNote(note, pages: nil) else { return }
        PrintService.print(pdfData: data, jobName: note.title)
    }
}

extension Notification.Name {
    static let scrollToPage = Notification.Name("SupaNotes.scrollToPage")
}
