import UIKit
import CoreGraphics

final class NoFadeTiledLayer: CATiledLayer {
    override class func fadeDuration() -> CFTimeInterval {
        return 0
    }
}

final class TiledBackgroundView: UIView {
    let pdfPage: CGPDFPage

    override class var layerClass: AnyClass {
        return NoFadeTiledLayer.self
    }

    init(pdfPage: CGPDFPage) {
        self.pdfPage = pdfPage
        super.init(frame: .zero)

        let tiledLayer = layer as! CATiledLayer
        tiledLayer.levelsOfDetail = 4
        tiledLayer.levelsOfDetailBias = 3
        tiledLayer.tileSize = CGSize(width: 512, height: 512)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        context.setFillColor(UIColor.blue.cgColor)
        context.fill(rect)

        let pageRect = pdfPage.getBoxRect(.mediaBox)

        context.saveGState()
        context.translateBy(x: 0, y: pageRect.height)
        context.scaleBy(x: 1, y: -1)
        context.drawPDFPage(pdfPage)
        context.restoreGState()
    }
}
