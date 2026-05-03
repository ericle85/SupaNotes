import UIKit

// MARK: - Drawing + Pencil Interaction
//
// DrawingCanvasDelegate: called when a live canvas begins/ends a pencil stroke.
// UIPencilInteractionDelegate: barrel double-tap.

extension MultipageCanvasContainer.Coordinator {

    func pageCanvasViewDidBeginUsingTool(_ view: DrawingCanvasView) -> Bool {
        // Stop any in-flight momentum so Pencil-down behaves like finger-down.
        if let scrollView {
            scrollView.stopScrollingAndZooming()
            onRequestStopScrollMomentum?(scrollView)
            onUndoManagerReady(view.undoManagerForPage)
            scrollView.isScrollEnabled = false
            return true
        }
        onUndoManagerReady(view.undoManagerForPage)
        return true
    }

    func pageCanvasViewDidEndUsingTool(_: DrawingCanvasView) {
        scrollView?.isScrollEnabled = true
    }

    func pencilInteractionDidTap(_: UIPencilInteraction) {
        onPencilDoubleTap?()
    }
}
