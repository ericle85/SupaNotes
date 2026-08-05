import SwiftUI

struct ZoomableCanvasRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> ZoomableCanvasView {
        return ZoomableCanvasView()
    }

    func updateUIView(_ uiView: ZoomableCanvasView, context: Context) {}
}

struct ContentView: View {
    var body: some View {
        ZoomableCanvasRepresentable()
            .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
}
