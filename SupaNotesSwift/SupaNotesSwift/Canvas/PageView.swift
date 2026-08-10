import CoreGraphics
import UIKit

final class PageView: UIView {
  private let background: PageBackground
  private let strokeLock = NSLock()
  private var strokes: [Stroke]
  private let activeStroke: ActiveStrokeView
  var onDrawingStateChanged: ((Bool) -> Void)? {
    get { activeStroke.onDrawingStateChanged }
    set { activeStroke.onDrawingStateChanged = newValue }
  }

  static let defaultPageSize = CGSize(width: 612, height: 792)

  override static var layerClass: AnyClass {
    return NoFadeTiledLayer.self
  }

  init(page: Page) {
    let pageSize = Self.pageSizeFor(page.background)
    let pageFrame = CGRect(origin: .zero, size: pageSize)

    self.background = page.background
    self.strokes = page.strokes
    activeStroke = ActiveStrokeView(frame: pageFrame)

    super.init(frame: pageFrame)

    contentScaleFactor = 1.0
    let tiledLayer = layer as! CATiledLayer
    tiledLayer.levelsOfDetail = 4
    tiledLayer.levelsOfDetailBias = 2
    tiledLayer.tileSize = CGSize(width: 512, height: 512)

    addSubview(activeStroke)

    activeStroke.onStrokeFinished = { [weak self] stroke in
      self?.addStroke(stroke)
    }
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError()
  }

  func updateActiveStrokeVisibleArea(rect: CGRect, zoomScale: CGFloat) {
    let localRect = convert(rect, from: superview)
    activeStroke.updateVisibleArea(rect: localRect, zoomScale: zoomScale)
  }

  func currentStrokes() -> [Stroke] {
    strokeLock.lock()
    let snapshot = strokes
    strokeLock.unlock()
    return snapshot
  }

  private func addStroke(_ stroke: Stroke) {
    strokeLock.lock()
    strokes.append(stroke)
    strokeLock.unlock()
    setNeedsDisplay(stroke.boundingRect)
  }

  override func draw(_ rect: CGRect) {
    guard let context = UIGraphicsGetCurrentContext() else {
      return
    }

    drawBackground(rect, into: context)
    drawStrokes(rect, into: context)
  }

  private func drawBackground(_ rect: CGRect, into context: CGContext) {
    switch background {
    case .grid(let theme):
      drawGrid(rect, theme: theme, into: context)
    case .pdf(let pdfPage):
      drawPDF(rect, page: pdfPage, into: context)
    }
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

  private func drawStrokes(_ rect: CGRect, into context: CGContext) {
    strokeLock.lock()
    let snapshot = strokes
    strokeLock.unlock()

    let visible = snapshot.filter { $0.boundingRect.intersects(rect) }

    for stroke in visible {
      let locations = stroke.points.map { $0.location }
      renderStroke(
        points: locations,
        color: stroke.color.cgColor,
        width: stroke.width,
        into: context
      )
    }
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
