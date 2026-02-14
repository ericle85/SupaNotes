import SwiftUI
import SwiftData
import PencilKit

struct NoteEditorView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(ToolbarState.self) private var toolbar
    @Query private var notes: [Note]
    @State private var canvasUndoManager: UndoManager?

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

    @ViewBuilder
    private func noteContent(_ note: Note) -> some View {
        @Bindable var toolbar = toolbar

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
                // Canvas
                CanvasView(
                    drawingData: Binding(
                        get: { note.drawingData },
                        set: { note.drawingData = $0 }
                    ),
                    tool: currentTool,
                    onUndoManagerReady: { canvasUndoManager = $0 },
                    onPencilDoubleTap: { toolbar.switchToPreviousTool() }
                )

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
        }
        .navigationTitle(note.title)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: note.drawingData) {
            note.updatedAt = .now
        }
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
