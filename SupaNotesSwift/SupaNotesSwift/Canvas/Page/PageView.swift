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
  let lineUnderlineLayer: CAShapeLayer
  let suggestionOverlay = MathSuggestionOverlay()
  let ghostLabel = makeGhostLabel()
  let textSuggestionBox = TextSuggestionBox()
  var lastHoveredIcon: UIImageView?
  private var isDrawing = false

  init(theme: GridTheme) {
    let frame = CGRect(origin: .zero, size: Self.pageSize)
    gridView = GridBackgroundView(frame: frame, theme: theme)
    boundingBoxLayer = makeBoundingBoxLayer()
    lineUnderlineLayer = makeLineUnderlineLayer()
    super.init(frame: frame)

    addSubview(gridView)
    setupCanvasView(frame: frame)
    canvasView.layer.addSublayer(boundingBoxLayer)
    canvasView.layer.addSublayer(lineUnderlineLayer)
    setupSuggestionOverlay(frame: frame)
    addSubview(ghostLabel)
    addSubview(textSuggestionBox)
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

  private func connectCollector() {
    strokeCollector.drawingProvider = { [weak self] in self?.canvasView.drawing ?? PKDrawing() }
    strokeCollector.onLinesChanged = { [weak self] rects in
      guard let self else { return }
      showLineUnderlines(rects, on: self.lineUnderlineLayer)
    }
    strokeCollector.onSuggestionNeeded = { [weak self] strokes in
      guard let self else { return }
      self.strokeCollector.isSuggestionActive = true
      Task {
        let suggestion = await generateSuggestion(strokes: strokes)
        await MainActor.run {
          guard !self.isDrawing, let suggestion else {
            self.strokeCollector.isSuggestionActive = false
            return
          }
          self.showGhostText(suggestion)
        }
      }
    }
  }

  func setDrawingWithUndo(_ newDrawing: PKDrawing, replacing oldDrawing: PKDrawing) {
    canvasView.drawing = newDrawing

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
    isDrawing = true
    onDrawingStateChanged?(true)
    hideGhostText()
  }

  func canvasViewDidEndUsingTool(_: PKCanvasView) {
    isDrawing = false
    onDrawingStateChanged?(false)
  }

  func canvasViewDrawingDidChange(_: PKCanvasView) {
    strokeCollector.pencilLifted()
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

  func showGhostText(_ suggestion: TextSuggestion) {
    ghostLabel.text = suggestion.text
    ghostLabel.font = UIFont.systemFont(ofSize: suggestion.lineHeight * 0.8)
    ghostLabel.sizeToFit()
    ghostLabel.frame.origin = CGPoint(
      x: suggestion.anchorX + 4,
      y: suggestion.lineYCenter - ghostLabel.frame.height / 2
    )
    ghostLabel.isHidden = false

    textSuggestionBox.show(
      currentText: suggestion.currentText,
      suggestion: suggestion.text,
      rightEdgeX: suggestion.anchorX,
      lineYCenter: suggestion.lineYCenter,
      lineHeight: suggestion.lineHeight
    )
  }

  func hideGhostText() {
    ghostLabel.isHidden = true
    ghostLabel.text = nil
    textSuggestionBox.hide()
    strokeCollector.isSuggestionActive = false
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError()
  }
}

private func makeGhostLabel() -> UILabel {
  let label = UILabel()
  label.textColor = UIColor.gray.withAlphaComponent(0.5)
  label.isHidden = true
  return label
}
