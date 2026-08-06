import CoreGraphics
import UIKit

final class TiledBackgroundView: UIView {
    let pdfPage: CGPDFPage

    override static var layerClass: AnyClass {
        return NoFadeTiledLayer.self
    }

    private let pageRect: CGRect

    init(pdfPage: CGPDFPage) {
        self.pdfPage = pdfPage
        self.pageRect = pdfPage.getBoxRect(.mediaBox)
        super.init(frame: .zero)

        contentScaleFactor = 1.0
        let tiledLayer = layer as! CATiledLayer
        tiledLayer.levelsOfDetail = 4
        tiledLayer.levelsOfDetailBias = 3
        tiledLayer.tileSize = CGSize(width: 512, height: 512)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        context.setFillColor(UIColor.white.cgColor)
        context.fill(rect)

        context.saveGState()
        context.translateBy(x: 0, y: pageRect.height)
        context.scaleBy(x: 1, y: -1)
        context.drawPDFPage(pdfPage)
        context.restoreGState()
    }
}
