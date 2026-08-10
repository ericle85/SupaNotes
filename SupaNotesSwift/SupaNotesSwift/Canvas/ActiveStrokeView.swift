import CoreGraphics
import UIKit

final class ActiveStrokeView: UIView {
  private var currentPoints: [StrokePoint] = []
  private let strokeColor: UIColor = .black
  private let strokeWidth: CGFloat = 4.0
  private var visiblePageRect: CGRect = .null

  var onStrokeFinished: ((Stroke) -> Void)?
  var onDrawingStateChanged: ((Bool) -> Void)?

  func updateVisibleArea(rect: CGRect, zoomScale: CGFloat) {
    visiblePageRect = bounds.intersection(rect)
    let newScale = zoomScale * traitCollection.displayScale
    if contentScaleFactor != newScale {
      contentScaleFactor = newScale
    }
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    isOpaque = false
    isMultipleTouchEnabled = false
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError()
  }

  override func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent?) {
    guard let touch = touches.first else {
      return
    }
    if touch.type != .pencil {
      return
    }

    let location = touch.location(in: self)
    let point = StrokePoint(
      location: location,
      force: touch.force,
      timestamp: touch.timestamp
    )
    currentPoints = [point]
    onDrawingStateChanged?(true)
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard let touch = touches.first else {
      return
    }
    if touch.type != .pencil {
      return
    }

    let coalesced = event?.coalescedTouches(for: touch) ?? [touch]

    for coalescedTouch in coalesced {
      let location = coalescedTouch.location(in: self)
      let point = StrokePoint(
        location: location,
        force: coalescedTouch.force,
        timestamp: coalescedTouch.timestamp
      )
      currentPoints.append(point)
    }

    setNeedsDisplay(visiblePageRect)
  }

  override func touchesEnded(_ touches: Set<UITouch>, with _: UIEvent?) {
    guard let touch = touches.first else {
      return
    }
    if touch.type != .pencil {
      return
    }

    if !currentPoints.isEmpty {
      let stroke = Stroke(
        points: currentPoints,
        color: strokeColor,
        width: strokeWidth
      )
      onStrokeFinished?(stroke)
    }
    onDrawingStateChanged?(false)
  }

  override func touchesCancelled(_: Set<UITouch>, with _: UIEvent?) {
    currentPoints = []
    setNeedsDisplay()
    onDrawingStateChanged?(false)
  }

  override func draw(_: CGRect) {
    guard !currentPoints.isEmpty else {
      return
    }
    guard let context = UIGraphicsGetCurrentContext() else {
      return
    }

    let locations = currentPoints.map { $0.location }
    renderStroke(
      points: locations,
      color: strokeColor.cgColor,
      width: strokeWidth,
      into: context
    )
  }
}
