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
        context.coordinator.drawingData = $drawingData
        canvasView.tool = tool
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(drawingData: $drawingData)
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        var drawingData: Binding<Data>
        weak var canvasView: PKCanvasView?

        init(drawingData: Binding<Data>) {
            self.drawingData = drawingData
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawingData.wrappedValue = canvasView.drawing.dataRepresentation()
        }
    }
}
