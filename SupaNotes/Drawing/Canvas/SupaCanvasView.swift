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
            let pen: Brush = try registerBrush(name: Self.penBrushName, textureID: nil)
            pen.opacity = 1.0
            pen.pointStep = 1
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
}
