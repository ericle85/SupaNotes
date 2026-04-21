import Foundation

final class DrawingSaveController {
    private var saveWorkItem: DispatchWorkItem?

    func debouncedSave(canvasView: SupaCanvasView, pages: [Page]) {
        let pageIndex = canvasView.pageIndex
        saveWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            let sorted = pages.sorted { $0.orderIndex < $1.orderIndex }
            guard sorted.indices.contains(pageIndex) else { return }
            guard let data = try? MaLiangDrawingCodec.encode(canvas: canvasView) else { return }
            sorted[pageIndex].drawingData = data
            sorted[pageIndex].drawingScale = 1.0
        }

        saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Design.Debounce.drawingSave, execute: workItem)
    }

    func immediateSave(canvasView: SupaCanvasView, pages: [Page]) {
        let sorted = pages.sorted { $0.orderIndex < $1.orderIndex }
        guard sorted.indices.contains(canvasView.pageIndex) else { return }
        saveWorkItem?.cancel()
        guard let data = try? MaLiangDrawingCodec.encode(canvas: canvasView) else { return }
        sorted[canvasView.pageIndex].drawingData = data
        sorted[canvasView.pageIndex].drawingScale = 1.0
    }
}
