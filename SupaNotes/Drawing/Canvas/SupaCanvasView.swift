import UIKit

final class SupaCanvasView: Canvas {
    static let penBrushName = "supanotes.pen"
    static let eraserBrushName = "supanotes.eraser"

    var pageIndex: Int = 0

    private var penBrush: Brush?
    private var eraserBrush: Eraser?

    override func setup() {
        super.setup()
        isPencilMode = true
        useFingersToErase = false
        backgroundColor = .clear

        do {
            let penTextureData = Self.makeSoftBrushTextureData()
            let pen: Brush = try registerBrush(name: Self.penBrushName, from: penTextureData)
            pen.opacity = 1.0
            pen.pointStep = 0.35
            pen.forceSensitive = 0
            penBrush = pen

            let eraser: Eraser = try registerBrush(name: Self.eraserBrushName, textureID: nil)
            eraser.opacity = 1.0
            eraser.pointStep = 1
            eraser.forceSensitive = 0
            eraserBrush = eraser
        } catch {
            penBrush = defaultBrush
            eraserBrush = nil
        }
    }

    func usePen(color: UIColor, width: CGFloat) {
        guard let penBrush else { return }
        penBrush.color = color
        penBrush.pointSize = max(1, width)
        penBrush.use()
    }

    func useEraser(width: CGFloat) {
        if let eraserBrush {
            eraserBrush.pointSize = max(4, width)
            eraserBrush.use()
        } else {
            defaultBrush.pointSize = max(4, width)
            defaultBrush.color = .clear
            defaultBrush.use()
        }
    }

    func brush(named name: String?) -> Brush {
        if name == Self.eraserBrushName, let eraserBrush {
            return eraserBrush
        }
        if name == Self.penBrushName, let penBrush {
            return penBrush
        }
        return defaultBrush
    }

    private static func makeSoftBrushTextureData(
        diameter: Int = 64,
        innerRadiusRatio: CGFloat = 0.82
    ) -> Data {
        let size = CGSize(width: diameter, height: diameter)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            let cgContext = context.cgContext
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let colors = [
                UIColor.white.withAlphaComponent(1).cgColor,
                UIColor.white.withAlphaComponent(1).cgColor,
                UIColor.white.withAlphaComponent(0).cgColor
            ] as CFArray
            let locations: [CGFloat] = [0, innerRadiusRatio, 1]
            guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) else {
                return
            }

            cgContext.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: radius,
                options: [.drawsAfterEndLocation]
            )
        }
        return image.pngData() ?? Data()
    }
}
