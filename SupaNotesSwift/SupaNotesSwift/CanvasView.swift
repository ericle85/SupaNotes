import CoreGraphics
import UIKit

final class CanvasView: UIView, UIScrollViewDelegate {
  private let scrollView = UIScrollView()
  private var tiledBackground: TiledBackgroundView?
  private var displayLink: CADisplayLink?
  private var zoomPhase: Double = 0
  private var zoomSpeed: Double = 0.5
  private let speedSlider = UISlider()
  private let toggleButton = UIButton(type: .system)

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .gray

    scrollView.delegate = self
    scrollView.minimumZoomScale = 0.25
    scrollView.maximumZoomScale = 10.0
    scrollView.bouncesZoom = true
    scrollView.showsVerticalScrollIndicator = false
    scrollView.showsHorizontalScrollIndicator = false
    addSubview(scrollView)

    if let bgView = makePDFBackground() {
      scrollView.addSubview(bgView)
      scrollView.contentSize = bgView.frame.size
      tiledBackground = bgView
    }

    let (toggle, slider) = makeDebugControls()
    addSubview(toggle)
    addSubview(slider)
  }

  required init?(coder: NSCoder) { fatalError() }

  private func makePDFBackground() -> TiledBackgroundView? {
    guard let pdfURL = Bundle.main.url(forResource: "Graph", withExtension: "pdf"),
      let document = CGPDFDocument(pdfURL as CFURL),
      let page = document.page(at: 1)
    else { return nil }
    let bgView = TiledBackgroundView(pdfPage: page)
    bgView.frame = CGRect(origin: .zero, size: page.getBoxRect(.mediaBox).size)
    return bgView
  }

  private func makeDebugControls() -> (UIButton, UISlider) {
    toggleButton.setTitle("Zoom Loop", for: .normal)
    toggleButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.8)
    toggleButton.setTitleColor(.white, for: .normal)
    toggleButton.layer.cornerRadius = 8
    toggleButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
    toggleButton.addTarget(self, action: #selector(toggleZoomLoop), for: .touchUpInside)

    speedSlider.minimumValue = 0.1
    speedSlider.maximumValue = 3.0
    speedSlider.value = 0.5
    speedSlider.addTarget(self, action: #selector(speedChanged), for: .valueChanged)
    speedSlider.isHidden = true

    return (toggleButton, speedSlider)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    scrollView.frame = bounds
    centerContent()
    toggleButton.frame = CGRect(x: 20, y: bounds.height - 100, width: 120, height: 40)
    speedSlider.frame = CGRect(x: 150, y: bounds.height - 95, width: 200, height: 30)
  }

  private func centerContent() {
    guard let bgView = tiledBackground else { return }

    let scrollBounds = scrollView.bounds
    let contentSize = bgView.frame.size

    let offsetX = max(0, (scrollBounds.width - contentSize.width) / 2)
    let offsetY = max(0, (scrollBounds.height - contentSize.height) / 2)

    scrollView.contentInset = UIEdgeInsets(
      top: offsetY,
      left: offsetX,
      bottom: offsetY,
      right: offsetX
    )
  }

  func viewForZooming(in scrollView: UIScrollView) -> UIView? {
    return tiledBackground
  }

  func scrollViewDidZoom(_ scrollView: UIScrollView) {
    centerContent()
  }

  @objc private func toggleZoomLoop() {
    if displayLink != nil {
      stopZoomLoop()
    } else {
      startZoomLoop()
    }
  }

  private func startZoomLoop() {
    zoomPhase = 0
    speedSlider.isHidden = false
    toggleButton.setTitle("Stop", for: .normal)
    toggleButton.backgroundColor = UIColor.systemRed.withAlphaComponent(0.8)

    let link = CADisplayLink(target: self, selector: #selector(zoomTick))
    link.add(to: .main, forMode: .common)
    displayLink = link
  }

  private func stopZoomLoop() {
    displayLink?.invalidate()
    displayLink = nil
    speedSlider.isHidden = true
    toggleButton.setTitle("Zoom Loop", for: .normal)
    toggleButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.8)
  }

  @objc private func speedChanged() {
    zoomSpeed = Double(speedSlider.value)
  }

  @objc private func zoomTick() {
    guard let link = displayLink else { return }
    zoomPhase += link.duration * zoomSpeed

    let normalized = (sin(zoomPhase) + 1) / 2
    let minScale = scrollView.minimumZoomScale
    let maxScale = scrollView.maximumZoomScale
    let scale = minScale + (maxScale - minScale) * normalized
    scrollView.zoomScale = scale
  }
}
