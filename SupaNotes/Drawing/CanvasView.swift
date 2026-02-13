import SwiftUI
import PencilKit

struct CanvasView: UIViewRepresentable {
    @Binding var drawingData: Data
    var tool: PKTool
    var onUndoManagerReady: (UndoManager?) -> Void
    var onPencilDoubleTap: (() -> Void)?

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.drawingPolicy = .pencilOnly
        canvasView.backgroundColor = .white
        canvasView.overrideUserInterfaceStyle = .light
        canvasView.tool = tool

        context.coordinator.canvasView = canvasView

        // Load drawing before setting delegate to avoid triggering canvasViewDrawingDidChange
        let drawing = (try? PKDrawing(data: drawingData)) ?? PKDrawing()
        canvasView.drawing = drawing

        canvasView.delegate = context.coordinator

        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = context.coordinator
        canvasView.addInteraction(pencilInteraction)

        DispatchQueue.main.async {
            onUndoManagerReady(canvasView.undoManager)
        }

        return canvasView
    }

    func updateUIView(_ canvasView: PKCanvasView, context: Context) {
        context.coordinator.drawingData = $drawingData
        context.coordinator.onPencilDoubleTap = onPencilDoubleTap
        canvasView.tool = tool
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(drawingData: $drawingData, onPencilDoubleTap: onPencilDoubleTap)
    }

    class Coordinator: NSObject, PKCanvasViewDelegate, UIPencilInteractionDelegate {
        var drawingData: Binding<Data>
        weak var canvasView: PKCanvasView?
        var onPencilDoubleTap: (() -> Void)?

        init(drawingData: Binding<Data>, onPencilDoubleTap: (() -> Void)?) {
            self.drawingData = drawingData
            self.onPencilDoubleTap = onPencilDoubleTap
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawingData.wrappedValue = canvasView.drawing.dataRepresentation()
        }

        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
            onPencilDoubleTap?()
        }
    }
}
