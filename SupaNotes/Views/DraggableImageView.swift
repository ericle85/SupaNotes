import SwiftUI

struct DraggableImageView: View {
    let noteImage: NoteImage

    @State private var dragOffset: CGSize = .zero
    @State private var currentScale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    var body: some View {
        if let uiImage = UIImage(data: noteImage.imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: noteImage.width * currentScale, height: noteImage.height * currentScale)
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(Color.accentColor.opacity(0.6))
                        .frame(width: 12, height: 12)
                        .padding(4)
                }
                .border(Color.accentColor.opacity(0.5), width: 1)
                .position(
                    x: noteImage.x + dragOffset.width,
                    y: noteImage.y + dragOffset.height
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation
                        }
                        .onEnded { value in
                            noteImage.x += value.translation.width
                            noteImage.y += value.translation.height
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
                            noteImage.width *= Double(currentScale)
                            noteImage.height *= Double(currentScale)
                            currentScale = 1.0
                            lastScale = 1.0
                        }
                )
        }
    }
}
