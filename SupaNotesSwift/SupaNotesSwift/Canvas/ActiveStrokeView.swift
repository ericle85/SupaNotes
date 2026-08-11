import CoreGraphics
import Metal
import UIKit

final class ActiveStrokeView: UIView {
  private var currentPoints: [StrokePoint] = []
  private let strokeColor: UIColor = .black
  private let strokeWidth: CGFloat = 4.0
  private let minimumPointDistance: CGFloat = 1.0
  private var dirtyRect: CGRect = .null
  private let gpuSmoothing: CatmullRomGPU

  var onStrokeFinished: ((Stroke) -> Void)?
  var onDrawingStateChanged: ((Bool) -> Void)?

  func updateContentScale(zoomScale: CGFloat) {
    let newScale = zoomScale * traitCollection.displayScale
    if contentScaleFactor != newScale {
      contentScaleFactor = newScale
    }
  }

  override init(frame: CGRect) {
    guard let device = MTLCreateSystemDefaultDevice(),
      let smoother = CatmullRomGPU(device: device)
    else { fatalError("Metal not available") }

    self.gpuSmoothing = smoother

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
      currentPoints = []
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
    #if DEBUG
      DebugFPSOverlay.recordDraw()
    #endif
    guard !currentPoints.isEmpty else {
      return
    }
    guard let context = UIGraphicsGetCurrentContext() else {
      return
    }

    let locations = currentPoints.map { $0.location }

    if locations.count == 1 {
      let radius = strokeWidth / 2
      let dotRect = CGRect(
        x: locations[0].x - radius,
        y: locations[0].y - radius,
        width: strokeWidth,
        height: strokeWidth
      )
      context.setFillColor(strokeColor.cgColor)
      context.fillEllipse(in: dotRect)
      return
    }

    let smoothed = gpuSmoothing.smooth(points: locations)

    let path = CGMutablePath()
    path.move(to: smoothed[0])
    for i in 1..<smoothed.count {
      path.addLine(to: smoothed[i])
    }

    context.setStrokeColor(strokeColor.cgColor)
    context.setLineWidth(strokeWidth)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.addPath(path)
    context.strokePath()
  }
}
