import SwiftUI
import PencilKit

struct NoteEditorView: View {
    @Bindable var note: Note
    @State private var selectedColor: Color = .primary
    @State private var penWidth: CGFloat = 3.0
    @State private var eraserWidth: CGFloat = 40.0
    @State private var isErasing = false
    @State private var canvasUndoManager: UndoManager?

    private var currentTool: PKTool {
        if isErasing {
            return PKEraserTool(.bitmap, width: eraserWidth)
        } else {
            return PKInkingTool(.pen, color: UIColor(selectedColor), width: penWidth)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Note Title", text: $note.title)
                .font(.title2)
                .padding(.horizontal)
                .padding(.vertical, 8)

            Divider()

            ZStack(alignment: .leading) {
                CanvasView(
                    drawingData: $note.drawingData,
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
