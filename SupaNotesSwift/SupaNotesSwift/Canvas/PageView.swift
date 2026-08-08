import CoreGraphics
import PencilKit
import UIKit

final class PageView: UIView {
  private var backgroundView: UIView?
  private let drawingCanvas = PKCanvasView()
  private let toolPicker = PKToolPicker()

  static let defaultPageSize = CGSize(width: 612, height: 792)

  init(page: Page) {
    let pageSize = Self.pageSizeFor(page.background)
    super.init(frame: CGRect(origin: .zero, size: pageSize))
    setBackground(page.background)
    setupDrawingCanvas(size: pageSize)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError()
  }

  private func setupDrawingCanvas(size: CGSize) {
    drawingCanvas.frame = CGRect(origin: .zero, size: size)
    drawingCanvas.isScrollEnabled = false
    drawingCanvas.backgroundColor = .clear
    drawingCanvas.isOpaque = false
    drawingCanvas.drawingPolicy = .pencilOnly
    addSubview(drawingCanvas)

    toolPicker.setVisible(true, forFirstResponder: drawingCanvas)
    toolPicker.addObserver(drawingCanvas)
    drawingCanvas.becomeFirstResponder()
  }

  private func setBackground(_ background: PageBackground) {
    backgroundView?.removeFromSuperview()

    let pageSize = Self.pageSizeFor(background)
    let bgView: UIView

    switch background {
    case .grid(let theme):
      bgView = GridBackgroundView(theme: theme, size: pageSize)
    case .pdf(let pdfPage):
      let pdfView = TiledBackgroundView(pdfPage: pdfPage)
      pdfView.frame = CGRect(origin: .zero, size: pageSize)
      bgView = pdfView
    }

    frame = CGRect(origin: frame.origin, size: pageSize)
    addSubview(bgView)
    backgroundView = bgView
  }

  static func pageSizeFor(_ background: PageBackground) -> CGSize {
    switch background {
    case .grid:
      return defaultPageSize
    case .pdf(let page):
      return page.getBoxRect(.mediaBox).size
    }
  }
}
