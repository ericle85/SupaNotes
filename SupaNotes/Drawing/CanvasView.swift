import SwiftUI
import PencilKit

struct CanvasView: UIViewRepresentable {
    @Binding var drawingData: Data
    var tool: PKTool
    var onUndoManagerReady: (UndoManager?) -> Void

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = .white
        canvasView.overrideUserInterfaceStyle = .light
        canvasView.tool = tool

        context.coordinator.canvasView = canvasView

        // Load drawing before setting delegate to avoid triggering canvasViewDrawingDidChange
        let drawing = (try? PKDrawing(data: drawingData)) ?? PKDrawing()
        canvasView.drawing = drawing

        canvasView.delegate = context.coordinator

        DispatchQueue.main.async {
            onUndoManagerReady(canvasView.undoManager)
        }

        return canvasView
    }

    func updateUIView(_ canvasView: PKCanvasView, context: Context) {
        let coordinator = context.coordinator
        coordinator.drawingData = $drawingData

        canvasView.tool = tool

        guard !coordinator.isUpdatingFromCanvas else { return }

        let currentData = canvasView.drawing.dataRepresentation()
        if currentData != drawingData {
            coordinator.isLoadingDrawing = true
            let drawing = (try? PKDrawing(data: drawingData)) ?? PKDrawing()
            canvasView.drawing = drawing
            coordinator.isLoadingDrawing = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(drawingData: $drawingData)
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        var drawingData: Binding<Data>
        var isUpdatingFromCanvas = false
        var isLoadingDrawing = false
        weak var canvasView: PKCanvasView?

        init(drawingData: Binding<Data>) {
            self.drawingData = drawingData
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isLoadingDrawing else { return }
            isUpdatingFromCanvas = true
            drawingData.wrappedValue = canvasView.drawing.dataRepresentation()
            DispatchQueue.main.async {
                self.isUpdatingFromCanvas = false
            }
        }
    }
}
