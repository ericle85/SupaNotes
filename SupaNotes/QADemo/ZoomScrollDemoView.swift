import SwiftUI

struct ZoomScrollDemoView: View {
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                Text(String(format: "Scale: %.2f", scale))
                    .accessibilityIdentifier(QAID.zoomScale)
                Text("Offset: \(Int(offset.width)), \(Int(offset.height))")
                    .accessibilityIdentifier(QAID.panOffset)
                Spacer()
                Button("Reset") {
                    scale = 1.0
                    offset = .zero
                }
                .accessibilityIdentifier(QAID.resetTransform)
            }
            .font(.headline)
            .padding(.horizontal)

            ZStack {
                LinearGradient(colors: [.purple, .orange],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Text("pinch · pan")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                    .scaleEffect(scale)
                    .offset(offset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .clipped()
            .gesture(
                MagnificationGesture()
                    .onChanged { scale = max(0.5, min($0, 5)) }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { offset = $0.translation }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier(QAID.zoomSurface)
        }
        .padding(.vertical)
        .navigationTitle("Zoom & Scroll")
        .explicitBack()
    }
}

#Preview { ZoomScrollDemoView() }
