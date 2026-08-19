import PencilKit
import UIKit

final class CanvasView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
  private let scrollView = UIScrollView()
  private let pageView: PageView
  private var momentumStopGesture: UIGestureRecognizer?
  private let shareButton = UIButton(type: .system)

  init(theme: GridTheme = .adaptive) {
    self.pageView = PageView(theme: theme)

    super.init(frame: .zero)
    backgroundColor = .systemGray3

    scrollView.delegate = self
    scrollView.minimumZoomScale = 0.75
    scrollView.maximumZoomScale = 2
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

    shareButton.setImage(
      UIImage(systemName: "square.and.arrow.up"), for: .normal)
    shareButton.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
    shareButton.translatesAutoresizingMaskIntoConstraints = false
    addSubview(shareButton)

    NSLayoutConstraint.activate([
      shareButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 12),
      shareButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
    ])

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

  @objc private func shareTapped() {
    let collector = pageView.strokeCollector
    let strokes = collector.lastPipelineStrokes
    if strokes.isEmpty {
      return
    }

    guard
      let folderURL = exportStrokeBundle(
        strokes: strokes, pipelineResult: collector.lastPipelineResult)
    else {
      return
    }

    let activityVC = UIActivityViewController(
      activityItems: [folderURL],
      applicationActivities: nil)
    activityVC.popoverPresentationController?.sourceView = shareButton
    activityVC.popoverPresentationController?.sourceRect = shareButton.bounds

    guard let windowScene = window?.windowScene,
      let rootVC = windowScene.keyWindow?.rootViewController
    else {
      return
    }
    rootVC.present(activityVC, animated: true)
  }

}
