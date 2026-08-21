import PencilKit
import UIKit

final class PageView: UIView, PKCanvasViewDelegate {
  let canvasView = PKCanvasView()
  let gridView: GridBackgroundView
  static let pageSize = CGSize(width: 612, height: 792)
  var onDrawingStateChanged: ((Bool) -> Void)?
  var toolPicker: PKToolPicker?
  let strokeCollector = StrokeCollector()
  let boundingBoxLayer: CAShapeLayer
  let suggestionOverlay = MathSuggestionOverlay()
  var lastHoveredIcon: UIImageView?

  init(theme: GridTheme) {
    let frame = CGRect(origin: .zero, size: Self.pageSize)
    gridView = GridBackgroundView(frame: frame, theme: theme)
    boundingBoxLayer = makeBoundingBoxLayer()
    super.init(frame: frame)

    addSubview(gridView)
    setupCanvasView(frame: frame)
    canvasView.layer.addSublayer(boundingBoxLayer)
    setupSuggestionOverlay(frame: frame)
    connectCollector()
    setupGestures()
  }

  private func setupGestures() {
    addGestureRecognizer(
      UITapGestureRecognizer(
        target: self, action: #selector(handleSuggestionTap(_:))
      ))
    addGestureRecognizer(
      UIHoverGestureRecognizer(
        target: self, action: #selector(handleSuggestionHover(_:))
      ))
  }

  private func setupCanvasView(frame: CGRect) {
    canvasView.frame = frame
    canvasView.drawingPolicy = .pencilOnly
    canvasView.backgroundColor = .clear
    canvasView.isOpaque = false
    canvasView.isScrollEnabled = false
    canvasView.tool = PKInkingTool(.pen, color: .black, width: 4)
    canvasView.delegate = self

    let pencilOnly = [UITouch.TouchType.pencil.rawValue as NSNumber]
    canvasView.gestureRecognizers?.forEach { $0.allowedTouchTypes = pencilOnly }

    addSubview(canvasView)
  }

  private func setupSuggestionOverlay(frame: CGRect) {
    suggestionOverlay.frame = frame
    suggestionOverlay.onAccept = { [weak self] in self?.acceptSuggestion(mathLabels: $0) }
    suggestionOverlay.onDeny = { [weak self] in self?.denySuggestion() }

    addSubview(suggestionOverlay)
  }

  private func handleBoundingBox(_ bbox: CGRect) {
    showBoundingBox(bbox, on: boundingBoxLayer)
  }

  private func handleScribble(bounds: CGRect, startIndex: Int) {
    applyScribbleErase(
      canvasView: canvasView,
      scribbleBounds: bounds,
      scribbleStartIndex: startIndex,
      boundingBoxLayer: boundingBoxLayer,
      onDrawingChanged: setDrawingWithUndo
    )
  }

  private func connectCollector() {
    strokeCollector.drawingProvider = { [weak self] in self?.canvasView.drawing ?? PKDrawing() }
    strokeCollector.onBoundingBox = { [weak self] in self?.handleBoundingBox($0) }
    strokeCollector.onScribbleDetected = { [weak self] in
      self?.handleScribble(bounds: $0, startIndex: $1)
    }
    strokeCollector.onSuggestion = { [weak self] in
      self?.showSuggestion(result: $0, strokes: $1, bbox: $2)
    }
  }

  func setDrawingWithUndo(_ newDrawing: PKDrawing, replacing oldDrawing: PKDrawing) {
    canvasView.drawing = newDrawing
    strokeCollector.syncStrokeCount()

    canvasView.undoManager?.registerUndo(withTarget: self) {
      $0.setDrawingWithUndo(oldDrawing, replacing: newDrawing)
    }
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    guard window != nil, toolPicker == nil else { return }

    let picker = PKToolPicker()
    picker.addObserver(canvasView)
    picker.setVisible(true, forFirstResponder: canvasView)
    toolPicker = picker
    canvasView.becomeFirstResponder()
  }

  func canvasViewDidBeginUsingTool(_: PKCanvasView) {
    onDrawingStateChanged?(true)
    suggestionOverlay.hide()
    strokeCollector.pencilTouched()
  }

  func canvasViewDidEndUsingTool(_: PKCanvasView) {
    onDrawingStateChanged?(false)
    strokeCollector.pencilLifted()
  }

  func canvasViewDrawingDidChange(_: PKCanvasView) {
    strokeCollector.syncIfStrokesRemoved()
  }

  private func eraserHitsSuggestion(at point: CGPoint) -> Bool {
    guard canvasView.tool is PKEraserTool else { return false }
    return subviews.contains { $0 is AcceptedSuggestionView && $0.frame.contains(point) }
  }

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    if suggestionButtonHit(at: point) { return self }
    if eraserHitsSuggestion(at: point) { return self }
    return super.hitTest(point, with: event)
  }

  func updateGridScale(zoomScale: CGFloat) {
    let scale = zoomScale * traitCollection.displayScale
    guard gridView.contentScaleFactor != scale else { return }
    gridView.contentScaleFactor = scale
    gridView.setNeedsDisplay()
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError()
  }
}
