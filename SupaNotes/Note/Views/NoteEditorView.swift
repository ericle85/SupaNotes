import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct NoteEditorView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(ToolbarState.self) private var toolbar
    @Environment(\.dismiss) private var dismiss
    // Gives us access to iOS undo/redo stack so toolbar buttons work.
    @Environment(\.undoManager) private var undoManager
    @Query private var notes: [Note]

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
        // For now we render only the first page on the letter-sized canvas.
        let currentPage = note.sortedPages.first

        ZStack {
            Color.white.ignoresSafeArea()

            // If we have at least one page, show the drawing surface.
            if let currentPage {
                ExcalidrawWritingSurface(
                    // Persist drawing bytes into this page model.
                    page: currentPage,
                    // Read current tool/color/width from shared toolbar state.
                    toolbar: toolbar,
                    // Connect canvas changes to undo/redo stack.
                    undoManager: undoManager,
                    // Update note timestamp when drawing changes.
                    onPageMutated: { note.updatedAt = .now }
                )
                // Let drawing area extend edge-to-edge behind top controls.
                .ignoresSafeArea()
            } else {
                // Fallback if somehow a note has zero pages.
                ContentUnavailableView("No Pages", systemImage: "doc")
            }

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

            // Floating toolbar (now receives real undo manager).
            DrawingToolbar(toolbar: toolbar, undoManager: undoManager)
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
            BookmarkListSheet(note: note, onTap: { _ in })
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

    private func editorTopActions(note: Note, pageManager _: PageManager) -> some View {
        HStack(spacing: 10) {
            Button { showingBookmarks = true } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: Design.FontSize.headerIcon, weight: .semibold))
                    .foregroundStyle(.primary)
                    .floatingButton()
            }

            Menu {
                Button { showingImport = true } label: { Label("Import PDF", systemImage: "square.and.arrow.down") }
                Button { showingExport = true } label: { Label("Export PDF", systemImage: "square.and.arrow.up") }
                Button { printNote(note) } label: { Label("Print", systemImage: "printer") }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: Design.FontSize.headerIcon, weight: .semibold))
                    .foregroundStyle(.primary)
                    .floatingButton()
            }
        }
    }

    private func handleImport(result: Result<URL, Error>, note: Note) {
        guard case let .success(url) = result else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        PDFService.importPDF(url: url, into: note, modelContext: modelContext)
    }

    private func printNote(_ note: Note) {
        guard let data = PDFService.exportNote(note, pages: nil) else { return }
        PrintService.print(pdfData: data, jobName: note.title)
    }
}

extension Notification.Name {
    static let scrollToPage = Notification.Name("SupaNotes.scrollToPage")
}
