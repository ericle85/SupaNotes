import CoreGraphics
import UIKit

final class CanvasView: UIView, UIScrollViewDelegate {
    private let scrollView = UIScrollView()
    private let contentContainer = UIView()
    private var pageView: PageView?

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
        setPage(Page(background: .grid(.dark)))

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

    func setPage(_ page: Page) {
        pageView?.removeFromSuperview()

        let newPageView = PageView(page: page)
        contentContainer.frame = CGRect(origin: .zero, size: newPageView.frame.size)
        contentContainer.addSubview(newPageView)
        scrollView.contentSize = newPageView.frame.size
        pageView = newPageView
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
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
    }
}
