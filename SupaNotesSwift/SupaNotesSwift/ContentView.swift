import SwiftUI

struct CanvasViewRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> CanvasView {
        return CanvasView()
    }

    func updateUIView(_ uiView: CanvasView, context: Context) {}
}

struct ContentView: View {
    var body: some View {
        CanvasViewRepresentable()
            .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
}
