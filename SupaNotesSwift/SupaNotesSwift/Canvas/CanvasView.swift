import UIKit

final class CanvasView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
  private let scrollView = UIScrollView()
  private let pageView: PageView
  private var momentumStopGesture: UIGestureRecognizer?

  init(theme: GridTheme = .light) {
    self.pageView = PageView(theme: theme)

    super.init(frame: .zero)
    backgroundColor = .gray

    scrollView.delegate = self
    scrollView.minimumZoomScale = 0.75
    scrollView.maximumZoomScale = 10.0
    scrollView.bouncesZoom = true
    scrollView.showsVerticalScrollIndicator = false
    scrollView.showsHorizontalScrollIndicator = false

    let fingerOnly = [UITouch.TouchType.direct.rawValue as NSNumber]
    scrollView.panGestureRecognizer.allowedTouchTypes = fingerOnly
    scrollView.pinchGestureRecognizer?.allowedTouchTypes = fingerOnly

    let stopMomentum = UILongPressGestureRecognizer(
      target: self, action: #selector(handleMomentumStop))
    stopMomentum.minimumPressDuration = 0
    stopMomentum.cancelsTouchesInView = false
    stopMomentum.delegate = self
    momentumStopGesture = stopMomentum

    addSubview(scrollView)
    scrollView.addGestureRecognizer(stopMomentum)
    scrollView.addSubview(pageView)

    pageView.onDrawingStateChanged = { [weak self] isDrawing in
      self?.setZoomEnabled(!isDrawing)
    }
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    scrollView.frame = bounds
    scrollView.contentSize = PageView.pageSize
    centerContent()
  }

  private func centerContent() {
    let scrollBounds = scrollView.bounds
    let contentSize = pageView.frame.size

    let offsetX = max(0, (scrollBounds.width - contentSize.width) / 2)
    let offsetY = max(0, (scrollBounds.height - contentSize.height) / 2)

    scrollView.contentInset = UIEdgeInsets(
      top: offsetY,
      left: offsetX,
      bottom: offsetY,
      right: offsetX
    )
  }

  @objc private func handleMomentumStop(_ gesture: UILongPressGestureRecognizer) {
    if gesture.state == .began, scrollView.isDecelerating {
      scrollView.setContentOffset(scrollView.contentOffset, animated: false)
    }
  }

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
  ) -> Bool {
    return gestureRecognizer === momentumStopGesture
  }

  private func setZoomEnabled(_ enabled: Bool) {
    scrollView.pinchGestureRecognizer?.isEnabled = enabled
    scrollView.panGestureRecognizer.isEnabled = enabled
  }

  func viewForZooming(in _: UIScrollView) -> UIView? {
    return pageView
  }

  func scrollViewDidZoom(_: UIScrollView) {
    centerContent()
  }

  func scrollViewDidEndZooming(_: UIScrollView, with _: UIView?, atScale scale: CGFloat) {
    pageView.updateGridScale(zoomScale: scale)
  }

}
