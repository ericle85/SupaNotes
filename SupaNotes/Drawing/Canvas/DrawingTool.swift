import UIKit

enum DrawingTool {
    case pen(color: UIColor, width: CGFloat)
    case eraser(width: CGFloat)

    func apply(to canvas: SupaCanvasView) {
        switch self {
        case let .pen(color, width):
            canvas.usePen(color: color, width: width)
        case let .eraser(width):
            canvas.useEraser(width: width)
        }
    }
}
