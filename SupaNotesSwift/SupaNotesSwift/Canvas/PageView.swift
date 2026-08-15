import PencilKit
import UIKit

final class PageView: UIView, PKCanvasViewDelegate {
  let canvasView = PKCanvasView()
  private let gridView: GridBackgroundView

  static let pageSize = CGSize(width: 612, height: 792)

  var onDrawingStateChanged: ((Bool) -> Void)?

  private var toolPicker: PKToolPicker?
  private let strokeCollector = StrokeCollector()
  private let boundingBoxLayer = CAShapeLayer()

  init(theme: GridTheme) {
    let frame = CGRect(origin: .zero, size: Self.pageSize)
    self.gridView = GridBackgroundView(frame: frame, theme: theme)

    super.init(frame: frame)

    addSubview(gridView)

    canvasView.frame = frame
    canvasView.drawingPolicy = .pencilOnly
    canvasView.backgroundColor = .clear
    canvasView.isOpaque = false
    canvasView.isScrollEnabled = false
    canvasView.tool = PKInkingTool(.pen, color: .black, width: 4)
    canvasView.delegate = self

    let pencilOnly = [UITouch.TouchType.pencil.rawValue as NSNumber]
    for recognizer in canvasView.gestureRecognizers ?? [] {
      recognizer.allowedTouchTypes = pencilOnly
    }

    addSubview(canvasView)

    boundingBoxLayer.fillColor = nil
    boundingBoxLayer.strokeColor = UIColor.systemBlue.cgColor
    boundingBoxLayer.lineWidth = 2.0
    boundingBoxLayer.lineDashPattern = [6, 4]
    boundingBoxLayer.isHidden = true
    canvasView.layer.addSublayer(boundingBoxLayer)

    strokeCollector.drawingProvider = { [weak self] in
      self?.canvasView.drawing ?? PKDrawing()
    }
    strokeCollector.onBoundingBox = { [weak self] rect in
      self?.showBoundingBox(rect)
    }
    strokeCollector.onScribbleDetected = { [weak self] bounds, startIndex in
      self?.applyScribbleErase(scribbleBounds: bounds, scribbleStartIndex: startIndex)
    }
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    guard let window, toolPicker == nil else { return }

    let picker = PKToolPicker()
    picker.selectedTool = PKInkingTool(.pen, color: .black, width: 4)
    picker.addObserver(canvasView)
    picker.setVisible(true, forFirstResponder: canvasView)
    toolPicker = picker
    canvasView.becomeFirstResponder()
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError()
  }

  func canvasViewDidBeginUsingTool(_: PKCanvasView) {
    onDrawingStateChanged?(true)
    strokeCollector.pencilTouched()
  }

  func canvasViewDidEndUsingTool(_: PKCanvasView) {
    onDrawingStateChanged?(false)
    strokeCollector.pencilLifted()
  }

  private func showBoundingBox(_ rect: CGRect) {
    let padded = rect.insetBy(dx: -4, dy: -4)
    boundingBoxLayer.path = UIBezierPath(roundedRect: padded, cornerRadius: 4).cgPath
    boundingBoxLayer.isHidden = false
  }

  private func applyScribbleErase(scribbleBounds: CGRect, scribbleStartIndex: Int) {
    let oldDrawing = canvasView.drawing
    let allStrokes = oldDrawing.strokes

    let preExisting = allStrokes.prefix(scribbleStartIndex)
    let overlappedByScribble = preExisting.filter { $0.renderBounds.intersects(scribbleBounds) }

    if overlappedByScribble.isEmpty {
      return
    }

    let scribbleStrokes = Array(allStrokes.suffix(from: scribbleStartIndex))
    let erasedStrokes = overlappedByScribble + scribbleStrokes
    let keptStrokes = Array(preExisting.filter { !$0.renderBounds.intersects(scribbleBounds) })

    let erasedDrawing = PKDrawing(strokes: erasedStrokes)
    let combinedBounds = erasedStrokes.reduce(CGRect.null) { $0.union($1.renderBounds) }
    let image = erasedDrawing.image(from: combinedBounds, scale: UIScreen.main.scale)

    let overlay = UIImageView(image: image)
    overlay.frame = combinedBounds
    canvasView.addSubview(overlay)

    let newDrawing = PKDrawing(strokes: keptStrokes)
    setDrawingWithUndo(newDrawing, replacing: oldDrawing)

    boundingBoxLayer.isHidden = true

    UIView.animate(
      withDuration: 0.3,
      animations: {
        overlay.alpha = 0
      },
      completion: { _ in
        overlay.removeFromSuperview()
      })
  }

  private func setDrawingWithUndo(_ newDrawing: PKDrawing, replacing oldDrawing: PKDrawing) {
    canvasView.drawing = newDrawing
    strokeCollector.syncStrokeCount()

    canvasView.undoManager?.registerUndo(withTarget: self) { pageView in
      pageView.setDrawingWithUndo(oldDrawing, replacing: newDrawing)
    }
  }

  func updateGridScale(zoomScale: CGFloat) {
    let newScale = zoomScale * traitCollection.displayScale
    if gridView.contentScaleFactor != newScale {
      gridView.contentScaleFactor = newScale
      gridView.setNeedsDisplay()
    }
  }
}

private final class GridBackgroundView: UIView {
  private let theme: GridTheme

  init(frame: CGRect, theme: GridTheme) {
    self.theme = theme
    super.init(frame: frame)
    backgroundColor = theme.backgroundColor
    contentMode = .redraw
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError()
  }

  override func draw(_ rect: CGRect) {
    guard let context = UIGraphicsGetCurrentContext() else {
      return
    }

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
}
