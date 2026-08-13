import CoreGraphics
import PencilKit
import UIKit

final class PageView: UIView, PKCanvasViewDelegate {
  private let background: PageBackground
  private let canvasView: PKCanvasView

  static let defaultPageSize = CGSize(width: 612, height: 792)

  var onDrawingStateChanged: ((Bool) -> Void)?

  init(page: Page) {
    let pageSize = Self.pageSizeFor(page.background)
    let pageFrame = CGRect(origin: .zero, size: pageSize)

    self.background = page.background
    self.canvasView = PKCanvasView(frame: pageFrame)

    super.init(frame: pageFrame)

    drawBackgroundImage()

    canvasView.drawing = page.drawing
    canvasView.drawingPolicy = .pencilOnly
    canvasView.backgroundColor = .clear
    canvasView.isOpaque = false
    canvasView.isScrollEnabled = false
    canvasView.tool = PKInkingTool(.pen, color: .black, width: 4)
    canvasView.delegate = self

    addSubview(canvasView)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError()
  }

  func currentDrawing() -> PKDrawing {
    return canvasView.drawing
  }

  func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
    onDrawingStateChanged?(true)
  }

  func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
    onDrawingStateChanged?(false)
  }

  private func drawBackgroundImage() {
    let pageSize = Self.pageSizeFor(background)
    let renderer = UIGraphicsImageRenderer(size: pageSize)
    let image = renderer.image { rendererContext in
      let context = rendererContext.cgContext
      let rect = CGRect(origin: .zero, size: pageSize)

      switch background {
      case .grid(let theme):
        drawGrid(rect, theme: theme, into: context)
      case .pdf(let pdfPage):
        drawPDF(rect, page: pdfPage, into: context)
      }
    }

    let backgroundView = UIImageView(image: image)
    backgroundView.frame = CGRect(origin: .zero, size: pageSize)
    insertSubview(backgroundView, at: 0)
  }

  private func drawGrid(_ rect: CGRect, theme: GridTheme, into context: CGContext) {
    context.setFillColor(theme.backgroundColor.cgColor)
    context.fill(rect)

    context.setStrokeColor(theme.lineColor.cgColor)
    context.setLineWidth(theme.lineWidth)

    let spacing = theme.spacing

    var x = floor(rect.minX / spacing) * spacing
    while x <= rect.maxX {
      context.move(to: CGPoint(x: x, y: rect.minY))
      context.addLine(to: CGPoint(x: x, y: rect.maxY))
      x += spacing
    }

    var y = floor(rect.minY / spacing) * spacing
    while y <= rect.maxY {
      context.move(to: CGPoint(x: rect.minX, y: y))
      context.addLine(to: CGPoint(x: rect.maxX, y: y))
      y += spacing
    }

    context.strokePath()
  }

  private func drawPDF(_ rect: CGRect, page pdfPage: CGPDFPage, into context: CGContext) {
    context.setFillColor(UIColor.white.cgColor)
    context.fill(rect)

    let pageRect = pdfPage.getBoxRect(.mediaBox)
    context.saveGState()
    context.translateBy(x: 0, y: pageRect.height)
    context.scaleBy(x: 1, y: -1)
    context.drawPDFPage(pdfPage)
    context.restoreGState()
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
