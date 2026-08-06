import CoreGraphics
import UIKit

final class PageView: UIView {
    private var backgroundView: UIView?

    static let defaultPageSize = CGSize(width: 612, height: 792)

    init(page: Page) {
        let pageSize = Self.pageSizeFor(page.background)
        super.init(frame: CGRect(origin: .zero, size: pageSize))
        setBackground(page.background)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    func setBackground(_ background: PageBackground) {
        backgroundView?.removeFromSuperview()

        let pageSize = Self.pageSizeFor(background)
        let bgView: UIView

        switch background {
        case let .grid(theme):
            bgView = GridBackgroundView(theme: theme, size: pageSize)
        case let .pdf(pdfPage):
            let pdfView = TiledBackgroundView(pdfPage: pdfPage)
            pdfView.frame = CGRect(origin: .zero, size: pageSize)
            bgView = pdfView
        }

        frame = CGRect(origin: frame.origin, size: pageSize)
        addSubview(bgView)
        backgroundView = bgView
    }

    static func pageSizeFor(_ background: PageBackground) -> CGSize {
        switch background {
        case .grid:
            return defaultPageSize
        case let .pdf(page):
            return page.getBoxRect(.mediaBox).size
        }
    }
}
