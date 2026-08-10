import CoreGraphics
import UIKit

final class CanvasView: UIView, UIScrollViewDelegate {
  private let scrollView = UIScrollView()
  private let contentContainer = UIView()

  private var pages: [Page] = []
  private var pageYOffsets: [CGFloat] = []
  private var pageSizes: [CGSize] = []
  private var visiblePageViews: [Int: PageView] = [:]
  private let pageGap: CGFloat = 20

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .gray

    scrollView.delegate = self
    scrollView.minimumZoomScale = 0.25
    scrollView.maximumZoomScale = 10.0
    scrollView.bouncesZoom = true
    scrollView.showsVerticalScrollIndicator = false
    scrollView.showsHorizontalScrollIndicator = false

    let fingerOnly = [UITouch.TouchType.direct.rawValue as NSNumber]
    scrollView.panGestureRecognizer.allowedTouchTypes = fingerOnly
    scrollView.pinchGestureRecognizer?.allowedTouchTypes = fingerOnly

    addSubview(scrollView)

    scrollView.addSubview(contentContainer)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError()
  }

  func setPages(_ newPages: [Page]) {
    for pageView in visiblePageViews.values {
      pageView.removeFromSuperview()
    }
    visiblePageViews.removeAll()
    pages = newPages
    precomputeLayout()
    setNeedsLayout()
  }

  private func precomputeLayout() {
    pageSizes = pages.map { PageView.pageSizeFor($0.background) }

    pageYOffsets = []
    var y: CGFloat = 0
    for (index, size) in pageSizes.enumerated() {
      pageYOffsets.append(y)
      y += size.height
      if index < pageSizes.count - 1 {
        y += pageGap
      }
    }
  }

  private func updateContentSize() {
    let totalHeight =
      pageYOffsets.isEmpty
      ? 0
      : pageYOffsets.last! + pageSizes.last!.height
    let containerWidth = pageSizes.map(\.width).max() ?? scrollView.bounds.width

    contentContainer.frame = CGRect(
      x: 0, y: 0,
      width: containerWidth,
      height: totalHeight
    )
    scrollView.contentSize = CGSize(width: containerWidth, height: totalHeight)
  }

  private func updateVisiblePages() {
    guard !pages.isEmpty else { return }

    let zoomScale = scrollView.zoomScale
    let visibleRect = CGRect(
      x: scrollView.contentOffset.x / zoomScale,
      y: scrollView.contentOffset.y / zoomScale,
      width: scrollView.bounds.width / zoomScale,
      height: scrollView.bounds.height / zoomScale
    )

    let bufferHeight = visibleRect.height
    let expandedMinY = visibleRect.minY - bufferHeight
    let expandedMaxY = visibleRect.maxY + bufferHeight

    var newVisibleIndices: Set<Int> = []
    for index in 0..<pages.count {
      let pageMinY = pageYOffsets[index]
      let pageMaxY = pageMinY + pageSizes[index].height
      if pageMaxY >= expandedMinY && pageMinY <= expandedMaxY {
        newVisibleIndices.insert(index)
      }
    }

    for index in visiblePageViews.keys {
      if !newVisibleIndices.contains(index) {
        let pageView = visiblePageViews.removeValue(forKey: index)!
        pages[index].strokes = pageView.currentStrokes()
        pageView.removeFromSuperview()
      }
    }

    let containerWidth = contentContainer.bounds.width
    for index in newVisibleIndices {
      let size = pageSizes[index]
      let x = (containerWidth - size.width) / 2
      let targetFrame = CGRect(
        x: x,
        y: pageYOffsets[index],
        width: size.width,
        height: size.height
      )

      if let existing = visiblePageViews[index] {
        existing.frame = targetFrame
      } else {
        let pageView = PageView(page: pages[index])
        pageView.frame = targetFrame
        contentContainer.addSubview(pageView)
        visiblePageViews[index] = pageView
        pageView.onDrawingStateChanged = { [weak self] isDrawing in
          self?.setZoomEnabled(!isDrawing)
        }
      }
    }

    for (_, pageView) in visiblePageViews {
      pageView.updateActiveStrokeVisibleArea(rect: visibleRect, zoomScale: zoomScale)
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    scrollView.frame = bounds
    updateContentSize()
    updateVisiblePages()
    centerContent()
  }

  private func centerContent() {
    let scrollBounds = scrollView.bounds
    let contentSize = contentContainer.frame.size

    let offsetX = max(0, (scrollBounds.width - contentSize.width) / 2)
    let offsetY = max(0, (scrollBounds.height - contentSize.height) / 2)

    scrollView.contentInset = UIEdgeInsets(
      top: offsetY,
      left: offsetX,
      bottom: offsetY,
      right: offsetX
    )
  }

  private func setZoomEnabled(_ enabled: Bool) {
    scrollView.pinchGestureRecognizer?.isEnabled = enabled
    scrollView.panGestureRecognizer.isEnabled = enabled
  }

  func viewForZooming(in _: UIScrollView) -> UIView? {
    return contentContainer
  }

  func scrollViewDidZoom(_: UIScrollView) {
    centerContent()
    updateVisiblePages()
  }

  func scrollViewDidScroll(_: UIScrollView) {
    updateVisiblePages()
  }
}
