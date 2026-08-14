import SwiftUI

struct CanvasViewRepresentable: UIViewRepresentable {
  func makeUIView(context _: Context) -> CanvasView {
    CanvasView()
  }

  func updateUIView(_: CanvasView, context _: Context) {}
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
