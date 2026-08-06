import CoreGraphics
import UIKit

final class NoFadePDFTiledLayer: CATiledLayer {
    override class func fadeDuration() -> CFTimeInterval {
        return 0
    }
}

final class TiledBackgroundView: UIView {
    let pdfPage: CGPDFPage

    override class var layerClass: AnyClass {
        return NoFadePDFTiledLayer.self
    }

    init(pdfPage: CGPDFPage) {
        self.pdfPage = pdfPage
        super.init(frame: .zero)

        contentScaleFactor = 1.0
        let tiledLayer = layer as! CATiledLayer
        tiledLayer.levelsOfDetail = 4
        tiledLayer.levelsOfDetailBias = 2
        tiledLayer.tileSize = CGSize(width: 512, height: 512)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        context.setFillColor(UIColor.white.cgColor)
        context.fill(rect)

        let pageRect = pdfPage.getBoxRect(.mediaBox)

        context.saveGState()
        context.translateBy(x: 0, y: pageRect.height)
        context.scaleBy(x: 1, y: -1)
        context.drawPDFPage(pdfPage)
        context.restoreGState()
    }
}
