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
    guard let url = Bundle.main.url(forResource: "ECE", withExtension: "pdf"),
      let document = CGPDFDocument(url as CFURL)
    else {
      return [Page(background: .grid(.dark))]
    }

    var pages: [Page] = []
    for i in 1...document.numberOfPages {
      guard let pdfPage = document.page(at: i) else { continue }
      pages.append(Page(background: .pdf(pdfPage)))
    }
    return pages
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
