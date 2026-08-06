import UIKit

final class PDFPageView: UIView {
    let pdfPage: CGPDFPage
    let pageSize: CGSize

    init(pdfPage: CGPDFPage) {
        self.pdfPage = pdfPage
        self.pageSize = pdfPage.getBoxRect(.mediaBox).size
        super.init(frame: CGRect(origin: .zero, size: pageSize))
        backgroundColor = .white
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(rect)

        context.saveGState()
        context.translateBy(x: 0, y: pageSize.height)
        context.scaleBy(x: 1, y: -1)
        context.drawPDFPage(pdfPage)
        context.restoreGState()
    }
}

final class CanvasView: UIView, UIScrollViewDelegate {
    private let scrollView = UIScrollView()
    private var pageView: PDFPageView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        setupScrollView()
        loadPDF()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupScrollView() {
        scrollView.delegate = self
        scrollView.maximumZoomScale = 8.0
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bouncesZoom = true
        addSubview(scrollView)
    }

    private func loadPDF() {
        guard let pdfURL = Bundle.main.url(forResource: "ECE", withExtension: "pdf"),
              let document = CGPDFDocument(pdfURL as CFURL),
              let page = document.page(at: 1) else { return }

        let pv = PDFPageView(pdfPage: page)
        scrollView.addSubview(pv)
        scrollView.contentSize = pv.frame.size
        pageView = pv
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds

        guard let pv = pageView else { return }
        let fitScale = min(bounds.width / pv.pageSize.width, bounds.height / pv.pageSize.height)
        scrollView.minimumZoomScale = fitScale
        if scrollView.zoomScale < fitScale {
            scrollView.zoomScale = fitScale
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return pageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        guard let pv = pageView else { return }
        let offsetX = max((scrollView.bounds.width - pv.frame.width) / 2, 0)
        let offsetY = max((scrollView.bounds.height - pv.frame.height) / 2, 0)
        scrollView.contentInset = UIEdgeInsets(top: offsetY, left: offsetX, bottom: offsetY, right: offsetX)
    }
}
