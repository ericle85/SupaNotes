import UIKit
import CoreGraphics

final class PDFTiledLayer: CATiledLayer {
    override class func fadeDuration() -> CFTimeInterval {
        return 0
    }
}

final class PDFBackgroundView: UIView {
    let pdfPage: CGPDFPage

    override class var layerClass: AnyClass {
        return PDFTiledLayer.self
    }

    init(pdfPage: CGPDFPage) {
        self.pdfPage = pdfPage
        super.init(frame: .zero)

        let tiledLayer = layer as! CATiledLayer
        tiledLayer.levelsOfDetail = 4
        tiledLayer.levelsOfDetailBias = 3
        tiledLayer.tileSize = CGSize(width: 512, height: 512)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        context.setFillColor(UIColor.black.cgColor)
        context.fill(rect)

        let pageRect = pdfPage.getBoxRect(.mediaBox)

        context.saveGState()
        context.translateBy(x: 0, y: pageRect.height)
        context.scaleBy(x: 1, y: -1)
        context.drawPDFPage(pdfPage)
        context.restoreGState()
    }
}

final class ZoomableCanvasView: UIView, UIScrollViewDelegate {
    private let scrollView = UIScrollView()
    private var pdfBackgroundView: PDFBackgroundView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupScrollView()
        loadPDFBackground()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupScrollView()
        loadPDFBackground()
    }

    private func setupScrollView() {
        scrollView.delegate = self
        scrollView.minimumZoomScale = 0.25
        scrollView.maximumZoomScale = 10.0
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    private func loadPDFBackground() {
        guard let pdfURL = Bundle.main.url(forResource: "GraphPaperBackground", withExtension: "pdf") else {
            return
        }
        guard let document = CGPDFDocument(pdfURL as CFURL) else {
            return
        }
        guard let page = document.page(at: 1) else {
            return
        }

        let pageRect = page.getBoxRect(.mediaBox)

        let bgView = PDFBackgroundView(pdfPage: page)
        bgView.frame = CGRect(origin: .zero, size: pageRect.size)

        scrollView.addSubview(bgView)
        scrollView.contentSize = pageRect.size

        pdfBackgroundView = bgView
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        centerContent()
    }

    private func centerContent() {
        guard let bgView = pdfBackgroundView else { return }

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
        return pdfBackgroundView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContent()
    }
}
