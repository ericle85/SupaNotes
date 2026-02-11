import SwiftUI
import PencilKit

struct CanvasView: UIViewRepresentable {
    @Binding var drawingData: Data
    @Binding var toolPickerIsActive: Bool

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = .systemBackground

        context.coordinator.canvasView = canvasView
        context.coordinator.toolPicker.addObserver(canvasView)

        // Load drawing before setting delegate to avoid triggering canvasViewDrawingDidChange
        let drawing = (try? PKDrawing(data: drawingData)) ?? PKDrawing()
        canvasView.drawing = drawing

        canvasView.delegate = context.coordinator
        context.coordinator.showToolPicker(toolPickerIsActive)

        return canvasView
    }

    func updateUIView(_ canvasView: PKCanvasView, context: Context) {
        let coordinator = context.coordinator

        // Keep binding reference current in case the note changed
        coordinator.drawingData = $drawingData

        guard !coordinator.isUpdatingFromCanvas else { return }

        let currentData = canvasView.drawing.dataRepresentation()
        if currentData != drawingData {
            coordinator.isLoadingDrawing = true
            let drawing = (try? PKDrawing(data: drawingData)) ?? PKDrawing()
            canvasView.drawing = drawing
            coordinator.isLoadingDrawing = false
        }

        coordinator.showToolPicker(toolPickerIsActive)
    }

    static func dismantleUIView(_ uiView: PKCanvasView, coordinator: Coordinator) {
        coordinator.toolPicker.setVisible(false, forFirstResponder: uiView)
        coordinator.toolPicker.removeObserver(uiView)
        uiView.resignFirstResponder()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(drawingData: $drawingData)
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        var drawingData: Binding<Data>
        var isUpdatingFromCanvas = false
        var isLoadingDrawing = false
        var toolPickerWasActive = false
        weak var canvasView: PKCanvasView?
        let toolPicker = PKToolPicker()

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

        func showToolPicker(_ isActive: Bool) {
            guard let canvasView else { return }
            if isActive {
                toolPicker.setVisible(true, forFirstResponder: canvasView)
                if !toolPickerWasActive {
                    canvasView.becomeFirstResponder()
                }
            } else {
                toolPicker.setVisible(false, forFirstResponder: canvasView)
            }
            toolPickerWasActive = isActive
        }
    }
}
