import CoreGraphics
import UIKit

enum PageBackground {
    case grid(GridTheme)
    case pdf(CGPDFPage)
}

final class CanvasView: UIView, UIScrollViewDelegate {
    private let scrollView = UIScrollView()
    private var backgroundView: UIView?
    private var debugZoom: DebugZoomAnimationController?

    private let canvasSize = CGSize(width: 612, height: 792)

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

        setBackground(.grid(.dark))

        let zoom = DebugZoomAnimationController(scrollView: scrollView)
        addSubview(zoom.toggleButton)
        addSubview(zoom.speedSlider)
        debugZoom = zoom
    }

    required init?(coder: NSCoder) { fatalError() }

    func setBackground(_ background: PageBackground) {
        backgroundView?.removeFromSuperview()

        let bgView: UIView
        switch background {
        case .grid(let theme):
            bgView = GridBackgroundView(theme: theme, size: canvasSize)
        case .pdf(let page):
            let pdfView = TiledBackgroundView(pdfPage: page)
            pdfView.frame = CGRect(origin: .zero, size: page.getBoxRect(.mediaBox).size)
            bgView = pdfView
        }

        scrollView.addSubview(bgView)
        scrollView.contentSize = bgView.frame.size
        backgroundView = bgView
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        centerContent()

        if let zoom = debugZoom {
            zoom.toggleButton.frame = CGRect(x: 20, y: bounds.height - 100, width: 120, height: 40)
            zoom.speedSlider.frame = CGRect(x: 150, y: bounds.height - 95, width: 200, height: 30)
        }
    }

    private func centerContent() {
        guard let bgView = backgroundView else { return }

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
        return backgroundView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContent()
    }
}
