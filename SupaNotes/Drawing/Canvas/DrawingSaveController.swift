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
            sorted[index].drawingData = drawing.dataRepresentation()
        }
        saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Design.Debounce.drawingSave, execute: workItem)
    }

    func immediateSave(canvasView: PKCanvasView, pages: [Page]) {
        let index = canvasView.tag
        let sorted = pages.sorted { $0.orderIndex < $1.orderIndex }
        guard index < sorted.count else { return }
        saveWorkItem?.cancel()
        sorted[index].drawingData = canvasView.drawing.dataRepresentation()
    }
}
