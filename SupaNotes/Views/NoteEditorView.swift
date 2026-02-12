import SwiftUI
import SwiftData
import PencilKit
import PhotosUI

struct NoteEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(ToolbarState.self) private var toolbar
    let noteID: PersistentIdentifier
    @State private var canvasUndoManager: UndoManager?
    @State private var showPhotoPicker = false
    @State private var selectedPhoto: PhotosPickerItem?

    private var note: Note? {
        modelContext.registeredModel(for: noteID) as Note?
    }

    private var currentTool: PKTool {
        switch toolbar.activeTool {
        case .pen:
            return PKInkingTool(.pen, color: UIColor(toolbar.selectedColor), width: toolbar.instrumentWidth(for: .pencil))
        case .eraser:
            return PKEraserTool(.bitmap, width: toolbar.instrumentWidth(for: .eraser))
        case .highlighter:
            return PKInkingTool(.marker, color: UIColor(toolbar.selectedColor), width: toolbar.instrumentWidth(for: .highlighter))
        case .lasso, .text:
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
                // Layer 1: Canvas
                CanvasView(
                    drawingData: Binding(
                        get: { note.drawingData },
                        set: { note.drawingData = $0 }
                    ),
                    tool: currentTool,
                    onUndoManagerReady: { canvasUndoManager = $0 }
                )

                // Layer 2: Transparent tap overlay for text tool
                if toolbar.activeTool == .text {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            addTextBox(to: note, at: location)
                        }
                }

                // Layer 3: Image overlays
                ForEach(note.images) { image in
                    DraggableImageView(noteImage: image)
                        .allowsHitTesting(toolbar.activeTool == .lasso || toolbar.activeTool == .text)
                }

                // Layer 4: Textbox overlays
                ForEach(note.textBoxes) { textBox in
                    DraggableTextBoxView(noteTextBox: textBox)
                        .allowsHitTesting(toolbar.activeTool == .lasso || toolbar.activeTool == .text)
                }

                // Layer 5: Toolbar
                DrawingToolbar(
                    toolbarIcons: $toolbar.toolbarIcons,
                    selectedColor: $toolbar.selectedColor,
                    activeTool: $toolbar.activeTool,
                    onImageRequested: { showPhotoPicker = true },
                    undoManager: canvasUndoManager
                )
                .padding(.leading, 12)
            }
            .id(note.id)
        }
        .navigationTitle(note.title)
        .navigationBarTitleDisplayMode(.inline)
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhoto, matching: .images)
        .onChange(of: selectedPhoto) {
            if let selectedPhoto {
                Task {
                    await loadImage(from: selectedPhoto, into: note)
                }
                self.selectedPhoto = nil
            }
        }
        .onChange(of: note.drawingData) {
            note.updatedAt = .now
        }
        .onChange(of: note.title) {
            note.updatedAt = .now
        }
        .onChange(of: toolbar.selectedColor) {
            toolbar.save(colorScheme: colorScheme)
        }
        .onChange(of: toolbar.activeTool) {
            toolbar.save(colorScheme: colorScheme)
        }
        .onChange(of: toolbar.toolbarIcons) {
            toolbar.save(colorScheme: colorScheme)
        }
    }

    // MARK: - Image Loading
    private func loadImage(from item: PhotosPickerItem, into note: Note) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }

        let noteImage = NoteImage(
            imageData: data,
            x: 200,
            y: 300,
            width: 250,
            height: 250
        )
        noteImage.note = note
        modelContext.insert(noteImage)
        note.updatedAt = .now

        // Switch to lasso mode so user can reposition
        await MainActor.run {
            toolbar.activeTool = .lasso
        }
    }

    // MARK: - Textbox Creation
    private func addTextBox(to note: Note, at location: CGPoint? = nil) {
        let textBox = NoteTextBox(
            text: "Text",
            x: Double(location?.x ?? 200),
            y: Double(location?.y ?? 300),
            width: 200,
            height: 60,
            fontSize: 18
        )
        textBox.note = note
        modelContext.insert(textBox)
        note.updatedAt = .now
    }
}
