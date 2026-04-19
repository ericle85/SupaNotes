import SwiftUI
import SwiftData
import PencilKit
import UniformTypeIdentifiers

struct NoteEditorView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(ToolbarState.self) private var toolbar
    @Environment(\.dismiss) private var dismiss
    @Query private var notes: [Note]
    @State private var canvasUndoManager: UndoManager?
    @State private var currentPageIndex: Int = 0

    private var note: Note? { notes.first }

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
            PagedCanvasContainer(
                pages: Binding(
                    get: { note.sortedPages },
                    set: { _ in }
                ),
                tool: toolbar.currentPKTool,
                onUndoManagerReady: { canvasUndoManager = $0 },
                onPencilDoubleTap: { toolbar.switchToPreviousTool() },
                onCurrentPageChanged: { currentPageIndex = $0 },
                addPage: { pageManager.addPage(to: note) },
                addPageAbove: { pageManager.addPageAbove(in: note) }
            )
            .ignoresSafeArea()

            // Home button
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

            DrawingToolbar(
                toolbar: toolbar,
                undoManager: canvasUndoManager
            )

            VStack {
                Spacer()
                HStack {
                    PageCounterView(currentPage: currentPageIndex, totalPages: note.pages.count)
                        .padding(.leading, Design.Spacing.pageCounterLeading)
                        .padding(.bottom, Design.Spacing.pageCounterBottom)
                    Spacer()
                }
            }
        }
        .navigationBarHidden(true)
        
        // Save whenever the user changes the color
        .onChange(of: toolbar.colorSelectedByUser) {
            toolbar.save(colorScheme: colorScheme)
        }
        
        // Save whenever the user switches tools (and remember the old one)
        .onChange(of: toolbar.currentlyActiveTool) { oldValue, newValue in
            if oldValue != newValue {
                toolbar.toolUsedPreviously = oldValue
            }
            toolbar.save(colorScheme: colorScheme)
        }
        
        // Save whenever the user rearranges the toolbar icons
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

    @ViewBuilder
    private func editorTopActions(note: Note, pageManager: PageManager) -> some View {
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
                Button { flushDrawings(); showingExport = true } label: { Label("Export PDF", systemImage: "square.and.arrow.up") }
                Button { flushDrawings(); printNote(note) } label: { Label("Print", systemImage: "printer") }
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
        if let idx = note.sortedPages.firstIndex(where: { $0.id == page.id }) {
            NotificationCenter.default.post(name: .scrollToPage, object: idx)
        }
    }

    private func handleImport(result: Result<URL, Error>, note: Note) {
        guard case .success(let url) = result else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        PDFService.importPDF(url: url, into: note, modelContext: modelContext)
    }

    private func flushDrawings() {
        NotificationCenter.default.post(name: Notification.Name("SupaNotes.flushDrawings"), object: nil)
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
