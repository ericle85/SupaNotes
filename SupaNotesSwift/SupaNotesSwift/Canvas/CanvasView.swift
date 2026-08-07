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

  #if DEBUG
    private var debugZoom: DebugZoomAnimationController?
  #endif

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

    scrollView.addSubview(contentContainer)

    #if DEBUG
      let zoom = DebugZoomAnimationController(scrollView: scrollView)
      addSubview(zoom.toggleButton)
      addSubview(zoom.speedSlider)
      debugZoom = zoom
    #endif
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

    let zoomScale = min(
      max(scrollView.zoomScale, scrollView.minimumZoomScale), scrollView.maximumZoomScale)
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
        visiblePageViews.removeValue(forKey: index)!.removeFromSuperview()
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
      }
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    scrollView.frame = bounds
    updateContentSize()
    updateVisiblePages()
    centerContent()

    #if DEBUG
      if let zoom = debugZoom {
        zoom.toggleButton.frame = CGRect(x: 20, y: bounds.height - 100, width: 120, height: 40)
        zoom.speedSlider.frame = CGRect(x: 150, y: bounds.height - 95, width: 200, height: 30)
      }
    #endif
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
