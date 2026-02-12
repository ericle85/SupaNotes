import SwiftUI

struct DraggableTextBoxView: View {
    let noteTextBox: NoteTextBox

    @State private var dragOffset: CGSize = .zero
    @State private var isEditing = false
    @State private var currentScale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    var body: some View {
        Group {
            if isEditing {
                TextEditor(text: Binding(
                    get: { noteTextBox.text },
                    set: { noteTextBox.text = $0 }
                ))
                .font(.system(size: noteTextBox.fontSize))
                .frame(width: noteTextBox.width, height: noteTextBox.height)
                .border(Color.accentColor, width: 2)
                .position(
                    x: noteTextBox.x + dragOffset.width,
                    y: noteTextBox.y + dragOffset.height
                )
                .onTapGesture {} // absorb taps while editing
            } else {
                Text(noteTextBox.text.isEmpty ? "Text" : noteTextBox.text)
                    .font(.system(size: noteTextBox.fontSize * currentScale))
                    .foregroundStyle(noteTextBox.text.isEmpty ? .secondary : .primary)
                    .frame(
                        width: noteTextBox.width * currentScale,
                        height: noteTextBox.height * currentScale,
                        alignment: .topLeading
                    )
                    .padding(4)
                    .border(Color.accentColor.opacity(0.5), width: 1)
                    .position(
                        x: noteTextBox.x + dragOffset.width,
                        y: noteTextBox.y + dragOffset.height
                    )
                    .onTapGesture(count: 2) {
                        isEditing = true
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                dragOffset = value.translation
                            }
                            .onEnded { value in
                                noteTextBox.x += value.translation.width
                                noteTextBox.y += value.translation.height
                                dragOffset = .zero
                            }
                    )
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in
                                currentScale = lastScale * value.magnification
                            }
                            .onEnded { value in
                                lastScale = currentScale
                                noteTextBox.width *= Double(currentScale)
                                noteTextBox.height *= Double(currentScale)
                                noteTextBox.fontSize *= Double(currentScale)
                                currentScale = 1.0
                                lastScale = 1.0
                            }
                    )
            }
        }
        .onTapGesture {
            if isEditing {
                isEditing = false
            }
        }
    }
}
