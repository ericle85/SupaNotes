import SwiftUI

struct NoteEditorView: View {
    @Bindable var note: Note
    @State private var toolPickerIsActive = true

    var body: some View {
        VStack(spacing: 0) {
            TextField("Note Title", text: $note.title)
                .font(.title2)
                .padding(.horizontal)
                .padding(.vertical, 8)

            Divider()

            CanvasView(drawingData: $note.drawingData, toolPickerIsActive: $toolPickerIsActive)
                .id(note.id)
        }
        .navigationTitle(note.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    toolPickerIsActive.toggle()
                } label: {
                    Image(systemName: toolPickerIsActive ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle")
                }
            }
        }
        .onChange(of: note.drawingData) {
            note.updatedAt = .now
        }
        .onChange(of: note.title) {
            note.updatedAt = .now
        }
    }
}
