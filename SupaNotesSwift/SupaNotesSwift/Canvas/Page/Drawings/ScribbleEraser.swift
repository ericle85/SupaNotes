import PencilKit
import UIKit

func applyScribbleErase(
    canvasView: PKCanvasView,
    scribbleBounds: CGRect,
    scribbleStartIndex: Int,
    boundingBoxLayer: CAShapeLayer,
    onDrawingChanged: (PKDrawing, PKDrawing) -> Void
) {
    let oldDrawing = canvasView.drawing
    let existing = oldDrawing.strokes.prefix(scribbleStartIndex)
    let erased = existing.filter { $0.renderBounds.intersects(scribbleBounds) }
    guard !erased.isEmpty else { return }

    let scribble = oldDrawing.strokes.dropFirst(scribbleStartIndex)
    let kept = existing.filter { !$0.renderBounds.intersects(scribbleBounds) }

    let erasedDrawing = PKDrawing(strokes: Array(erased) + scribble)
    let bounds = (Array(erased) + scribble).reduce(CGRect.null) { $0.union($1.renderBounds) }

    let image = erasedDrawing.image(from: bounds, scale: canvasView.traitCollection.displayScale)
    let overlay = UIImageView(image: image)
    overlay.frame = bounds
    canvasView.addSubview(overlay)

    let newDrawing = PKDrawing(strokes: Array(kept))
    onDrawingChanged(newDrawing, oldDrawing)
    boundingBoxLayer.isHidden = true

    UIView.animate(withDuration: 0.3, animations: { overlay.alpha = 0 }) { _ in
        overlay.removeFromSuperview()
    }
}
