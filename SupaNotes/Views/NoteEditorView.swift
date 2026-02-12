import SwiftUI
import SwiftData
import PencilKit

struct NoteEditorView: View {
    @Environment(\.modelContext) private var modelContext
    let noteID: PersistentIdentifier
    @State private var selectedColor: Color = .primary
    @State private var penWidth: CGFloat = 3.0
    @State private var eraserWidth: CGFloat = 40.0
    @State private var isErasing = false
    @State private var canvasUndoManager: UndoManager?

    private var note: Note? {
        modelContext.model(for: noteID) as? Note
    }

    private var currentTool: PKTool {
        if isErasing {
            return PKEraserTool(.bitmap, width: eraserWidth)
        } else {
            return PKInkingTool(.pen, color: UIColor(selectedColor), width: penWidth)
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
                CanvasView(
                    drawingData: Binding(
                        get: { note.drawingData },
                        set: { note.drawingData = $0 }
                    ),
                    tool: currentTool,
                    onUndoManagerReady: { canvasUndoManager = $0 }
                )

                DrawingToolbar(
                    selectedColor: $selectedColor,
                    penWidth: $penWidth,
                    eraserWidth: $eraserWidth,
                    isErasing: $isErasing,
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
    }
}
