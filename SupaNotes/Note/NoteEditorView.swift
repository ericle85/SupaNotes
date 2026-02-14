import SwiftUI
import SwiftData
import PencilKit

struct NoteEditorView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(ToolbarState.self) private var toolbar
    @Query private var notes: [Note]
    @State private var canvasUndoManager: UndoManager?
    @State private var currentPageIndex: Int = 0
    @State private var revertToPenAfterNextErase = false

    private var note: Note? { notes.first }

    init(noteID: UUID) {
        _notes = Query(filter: #Predicate<Note> { note in
            note.id == noteID
        })
    }

    private var currentTool: PKTool {
        switch toolbar.activeTool {
        case .pen:
            return PKInkingTool(.pen, color: UIColor(toolbar.selectedColor), width: toolbar.instrumentWidth(for: .pencil))
        case .eraser:
            return PKEraserTool(.bitmap, width: toolbar.instrumentWidth(for: .eraser))
        case .highlighter:
            return PKInkingTool(.marker, color: UIColor(toolbar.selectedColor), width: toolbar.instrumentWidth(for: .highlighter))
        case .lasso:
            return PKLassoTool()
        }
    }

    var body: some View {
        if let note {
            noteContent(note)
        } else {
            ContentUnavailableView("Note not found", systemImage: "exclamationmark.triangle")
        }
    }

    /// Sorted pages for this note; ensures at least one page (migrates from legacy drawingData if needed).
    private func ensuredPages(for note: Note) -> [Page] {
        if note.pages.isEmpty {
            let page = Page(drawingData: note.drawingData, sortOrder: 0)
            page.note = note
            note.pages.append(page)
            try? modelContext.save()
        }
        return note.pages.sorted { $0.sortOrder < $1.sortOrder }
    }

    @ViewBuilder
    private func noteContent(_ note: Note) -> some View {
        @Bindable var toolbar = toolbar
        let pages = ensuredPages(for: note)

        VStack(spacing: 0) {
            TextField("Note Title", text: Binding(
                get: { note.title },
                set: { note.title = $0 }
            ))
            .font(.title2)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            ZStack(alignment: .leading) {
                TabView(selection: $currentPageIndex) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        CanvasView(
                            drawingData: Binding(
                                get: { page.drawingData },
                                set: {
                                    page.drawingData = $0
                                    note.updatedAt = .now
                                }
                            ),
                            tool: currentTool,
                            onUndoManagerReady: { canvasUndoManager = $0 },
                            onPencilDoubleTap: { toolbar.switchToPreviousTool() },
                            onScratchDetected: {
                                toolbar.activeTool = .eraser
                                revertToPenAfterNextErase = true
                            },
                            onEraseStrokeComplete: {
                                if revertToPenAfterNextErase {
                                    toolbar.activeTool = toolbar.previousTool
                                    revertToPenAfterNextErase = false
                                }
                            }
                        )
                        .id(page.id)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .indexViewStyle(.page(backgroundDisplayMode: .never))

                // Toolbar
                DrawingToolbar(
                    toolbarIcons: $toolbar.toolbarIcons,
                    selectedColor: $toolbar.selectedColor,
                    activeTool: $toolbar.activeTool,
                    undoManager: canvasUndoManager
                )
                .padding(.leading, 12)
            }
            .id(note.id)

            // Page controls
            HStack(spacing: 16) {
                Text("Page \(currentPageIndex + 1) of \(pages.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    let newPage = Page(drawingData: Data(), sortOrder: (note.pages.map(\.sortOrder).max() ?? -1) + 1)
                    newPage.note = note
                    note.pages.append(newPage)
                    currentPageIndex = note.pages.count - 1
                    note.updatedAt = .now
                    try? modelContext.save()
                } label: {
                    Image(systemName: "plus.rectangle.on.rectangle")
                }
                if pages.count > 1 {
                    Button(role: .destructive) {
                        let sorted = note.pages.sorted { $0.sortOrder < $1.sortOrder }
                        guard currentPageIndex >= 0, currentPageIndex < sorted.count else { return }
                        let toRemove = sorted[currentPageIndex]
                        note.pages.removeAll { $0.id == toRemove.id }
                        modelContext.delete(toRemove)
                        currentPageIndex = min(currentPageIndex, max(0, note.pages.count - 1))
                        note.updatedAt = .now
                        try? modelContext.save()
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .navigationTitle(note.title)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: note.title) {
            note.updatedAt = .now
        }
        .onChange(of: toolbar.selectedColor) {
            toolbar.save(colorScheme: colorScheme)
        }
        .onChange(of: toolbar.activeTool) { oldValue, newValue in
            if oldValue != newValue {
                toolbar.previousTool = oldValue
            }
            toolbar.save(colorScheme: colorScheme)
        }
        .onChange(of: toolbar.toolbarIcons) {
            toolbar.save(colorScheme: colorScheme)
        }
    }
}
