import SwiftUI

struct CanvasViewRepresentable: UIViewRepresentable {
  func makeUIView(context _: Context) -> CanvasView {
    let canvas = CanvasView()
    let strokes = makeTextStrokes(
      text: "Hello World",
      origin: CGPoint(x: 50, y: 100),
      scale: 4
    )
    let pages = [Page(background: .grid(.light), strokes: strokes)]
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
