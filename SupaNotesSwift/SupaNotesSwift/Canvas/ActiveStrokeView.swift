import CoreGraphics
import UIKit

final class ActiveStrokeView: UIView {
  private var currentPoints: [StrokePoint] = []
  private let strokeColor: UIColor = .black
  private let strokeWidth: CGFloat = 4.0
  private let minimumPointDistance: CGFloat = 0.2
  private var dirtyRect: CGRect = .null
  private var commitGeneration: Int = 0

  var onStrokeFinished: ((Stroke) -> Void)?
  var onDrawingStateChanged: ((Bool) -> Void)?

  func updateContentScale(zoomScale: CGFloat) {
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
    commitGeneration += 1
    currentPoints = [point]
    onDrawingStateChanged?(true)
    setNeedsDisplay()
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard let touch = touches.first else {
      return
    }
    if touch.type != .pencil {
      return
    }

    let coalesced = event?.coalescedTouches(for: touch) ?? [touch]
    let padding = strokeWidth * 2
    let pointCountBefore = currentPoints.count

    for coalescedTouch in coalesced {
      let location = coalescedTouch.location(in: self)

      if let lastLocation = currentPoints.last?.location {
        let deltaX = location.x - lastLocation.x
        let deltaY = location.y - lastLocation.y
        if deltaX * deltaX + deltaY * deltaY < minimumPointDistance * minimumPointDistance {
          continue
        }
      }

      let point = StrokePoint(
        location: location,
        force: coalescedTouch.force,
        timestamp: coalescedTouch.timestamp
      )
      currentPoints.append(point)

      let pointRect = CGRect(
        x: location.x - padding,
        y: location.y - padding,
        width: padding * 2,
        height: padding * 2
      )
      dirtyRect = dirtyRect.isNull ? pointRect : dirtyRect.union(pointRect)
    }

    if currentPoints.count == pointCountBefore {
      return
    }

    if pointCountBefore >= 1 {
      let prev = currentPoints[pointCountBefore - 1]
      let prevRect = CGRect(
        x: prev.location.x - padding,
        y: prev.location.y - padding,
        width: padding * 2,
        height: padding * 2
      )
      dirtyRect = dirtyRect.union(prevRect)
    }

    setNeedsDisplay(dirtyRect)
    dirtyRect = .null
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
      let gen = commitGeneration
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
        guard let self, self.commitGeneration == gen else { return }
        self.currentPoints = []
        self.setNeedsDisplay()
      }
    }
    onDrawingStateChanged?(false)
  }

  override func touchesCancelled(_: Set<UITouch>, with _: UIEvent?) {
    currentPoints = []
    setNeedsDisplay()
    onDrawingStateChanged?(false)
  }

  override func draw(_: CGRect) {
    #if DEBUG
      DebugFPSOverlay.recordDraw()
    #endif
    guard !currentPoints.isEmpty else {
      return
    }
    guard let context = UIGraphicsGetCurrentContext() else {
      return
    }

    renderStroke(
      points: currentPoints.map { $0.location },
      color: strokeColor.cgColor,
      width: strokeWidth,
      into: context
    )
  }
}
