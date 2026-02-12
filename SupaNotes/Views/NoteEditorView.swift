import SwiftUI
import SwiftData
import PencilKit

struct NoteEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(ToolbarState.self) private var toolbar
    let noteID: PersistentIdentifier
    @State private var canvasUndoManager: UndoManager?

    private var note: Note? {
        modelContext.registeredModel(for: noteID) as Note?
    }

    private var currentTool: PKTool {
        if toolbar.isErasing {
            return PKEraserTool(.bitmap, width: toolbar.eraserWidth)
        } else {
            return PKInkingTool(.pen, color: UIColor(toolbar.selectedColor), width: toolbar.penWidth)
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
                CanvasView(
                    drawingData: Binding(
                        get: { note.drawingData },
                        set: { note.drawingData = $0 }
                    ),
                    tool: currentTool,
                    onUndoManagerReady: { canvasUndoManager = $0 }
                )

                DrawingToolbar(
                    toolbarIcons: $toolbar.toolbarIcons,
                    selectedColor: $toolbar.selectedColor,
                    penWidth: $toolbar.penWidth,
                    eraserWidth: $toolbar.eraserWidth,
                    isErasing: $toolbar.isErasing,
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
        .onChange(of: toolbar.penWidth) {
            toolbar.save(colorScheme: colorScheme)
        }
        .onChange(of: toolbar.eraserWidth) {
            toolbar.save(colorScheme: colorScheme)
        }
        .onChange(of: toolbar.isErasing) {
            toolbar.save(colorScheme: colorScheme)
        }
        .onChange(of: toolbar.toolbarIcons) {
            toolbar.save(colorScheme: colorScheme)
        }
    }
}
