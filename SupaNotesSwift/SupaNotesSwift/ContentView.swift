import SwiftUI

struct CanvasViewRepresentable: UIViewRepresentable {
  func makeUIView(context _: Context) -> CanvasView {
    let canvas = CanvasView()
    let pages = loadPDFPages()
    canvas.setPages(pages)
    return canvas
  }

  func updateUIView(_: CanvasView, context _: Context) {}

  private func loadPDFPages() -> [Page] {
    let drawing = makeTextDrawing(
      text: "Hello World",
      origin: CGPoint(x: 50, y: 100),
      scale: 4
    )
    return [Page(background: .grid(.light), initialDrawing: drawing)]
  }
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
