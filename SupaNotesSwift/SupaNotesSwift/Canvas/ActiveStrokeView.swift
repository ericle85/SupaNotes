import CoreGraphics
import Metal
import QuartzCore
import UIKit

final class ActiveStrokeView: UIView {
  private var currentPoints: [StrokePoint] = []
  private let strokeColor: UIColor = .black
  private let strokeWidth: CGFloat = 4.0
  private let minimumPointDistance: CGFloat = 1.0
  private let renderer: MetalStrokeRenderer
  private let metalLayer = CAMetalLayer()

  var onStrokeFinished: ((Stroke) -> Void)?
  var onDrawingStateChanged: ((Bool) -> Void)?

  func updateContentScale(zoomScale: CGFloat) {
    let newScale = zoomScale * traitCollection.displayScale
    if metalLayer.contentsScale != newScale {
      metalLayer.contentsScale = newScale
      updateDrawableSize()
      if currentPoints.isEmpty {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
          guard let self, self.currentPoints.isEmpty else { return }
          self.metalLayer.isHidden = true
        }
      }
    }
  }

  override init(frame: CGRect) {
    guard let device = MTLCreateSystemDefaultDevice(),
      let metalRenderer = MetalStrokeRenderer(device: device)
    else { fatalError("Metal not available") }

    self.renderer = metalRenderer

    super.init(frame: frame)

    backgroundColor = .clear
    isOpaque = false
    isMultipleTouchEnabled = false

    metalLayer.device = device
    metalLayer.pixelFormat = .bgra8Unorm
    metalLayer.isOpaque = false
    metalLayer.framebufferOnly = true
    metalLayer.frame = bounds
    metalLayer.isHidden = true
    layer.addSublayer(metalLayer)
    updateDrawableSize()
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    metalLayer.frame = bounds
    updateDrawableSize()
  }

  private func updateDrawableSize() {
    let scale = metalLayer.contentsScale
    metalLayer.drawableSize = CGSize(
      width: bounds.width * scale,
      height: bounds.height * scale
    )
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
    metalLayer.isHidden = false
    onDrawingStateChanged?(true)
    renderFrame()
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
    }

    renderFrame()
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
    renderFrame()
    onDrawingStateChanged?(false)
  }

  private func renderFrame() {
    guard let drawable = metalLayer.nextDrawable() else {
      return
    }

    if currentPoints.isEmpty {
      renderer.clear(drawable: drawable)
      return
    }

    let locations = currentPoints.map { $0.location }
    renderer.render(
      points: locations,
      color: strokeColor,
      width: strokeWidth,
      to: drawable,
      viewportSize: bounds.size
    )
  }
}
