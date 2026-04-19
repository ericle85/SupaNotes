import PencilKit

class DrawingSaveController {
    private var saveWorkItem: DispatchWorkItem?

    func debouncedSave(canvasView: PKCanvasView, pages: [Page]) {
        let index = canvasView.tag
        let drawing = canvasView.drawing

        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            let sorted = pages.sorted { $0.orderIndex < $1.orderIndex }
            guard index < sorted.count else { return }
            let storageDrawing = Self.storageDrawing(for: canvasView, drawing: drawing)
            sorted[index].drawingData = storageDrawing.dataRepresentation()
            sorted[index].drawingScale = Double(DrawingCoordinateSpace.storageScale)
        }
        saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Design.Debounce.drawingSave, execute: workItem)
    }

    func immediateSave(canvasView: PKCanvasView, pages: [Page]) {
        let index = canvasView.tag
        let sorted = pages.sorted { $0.orderIndex < $1.orderIndex }
        guard index < sorted.count else { return }
        saveWorkItem?.cancel()
        let storageDrawing = Self.storageDrawing(for: canvasView, drawing: canvasView.drawing)
        sorted[index].drawingData = storageDrawing.dataRepresentation()
        sorted[index].drawingScale = Double(DrawingCoordinateSpace.storageScale)
    }

    private static func storageDrawing(for canvasView: PKCanvasView, drawing: PKDrawing) -> PKDrawing {
        let presentationScale = (canvasView as? SupaCanvasView)?.presentationScale ?? 1.0
        return DrawingCoordinateSpace.storageDrawing(fromPresentation: drawing, presentationScale: presentationScale)
    }
}
