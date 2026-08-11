import SwiftUI

struct CanvasViewRepresentable: UIViewRepresentable {
  func makeUIView(context _: Context) -> CanvasView {
    let canvas = CanvasView()
    let pages = [Page(background: .grid(.light))]
    canvas.setPages(pages)
    return canvas
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
