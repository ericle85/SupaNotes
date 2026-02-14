import SwiftUI
import PencilKit

struct CanvasView: UIViewRepresentable {
    @Binding var drawingData: Data
    var tool: PKTool
    var onUndoManagerReady: (UndoManager?) -> Void
    var onPencilDoubleTap: (() -> Void)?
    var onScratchDetected: (() -> Void)?
    var onEraseStrokeComplete: (() -> Void)?

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

        context.coordinator.startObservingUndo(canvasView.undoManager)

        return canvasView
    }

    func updateUIView(_ canvasView: PKCanvasView, context: Context) {
        context.coordinator.drawingData = $drawingData
        context.coordinator.onPencilDoubleTap = onPencilDoubleTap
        context.coordinator.onScratchDetected = onScratchDetected
        context.coordinator.onEraseStrokeComplete = onEraseStrokeComplete
        canvasView.tool = tool
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(drawingData: $drawingData, onPencilDoubleTap: onPencilDoubleTap, onScratchDetected: onScratchDetected, onEraseStrokeComplete: onEraseStrokeComplete)
    }

    class Coordinator: NSObject, PKCanvasViewDelegate, UIPencilInteractionDelegate {
        var drawingData: Binding<Data>
        weak var canvasView: PKCanvasView?
        var onPencilDoubleTap: (() -> Void)?
        var onScratchDetected: (() -> Void)?
        var onEraseStrokeComplete: (() -> Void)?

        // Scratch detection: quick scribble = multiple strokes in short time in small region
        private var previousStrokeCount = 0
        private var firstStrokeAddTime: Date?
        private var recentStrokeAddCount = 0
        private let scratchTimeWindow: TimeInterval = 0.5
        private let scratchMinStrokes = 3

        private var undoJustPerformed = false
        private var undoObserver: NSObjectProtocol?

        init(drawingData: Binding<Data>, onPencilDoubleTap: (() -> Void)?, onScratchDetected: (() -> Void)?, onEraseStrokeComplete: (() -> Void)?) {
            self.drawingData = drawingData
            self.onPencilDoubleTap = onPencilDoubleTap
            self.onScratchDetected = onScratchDetected
            self.onEraseStrokeComplete = onEraseStrokeComplete
        }

        func startObservingUndo(_ undoManager: UndoManager) {
            guard undoObserver == nil else { return }
            undoObserver = NotificationCenter.default.addObserver(forName: .NSUndoManagerDidUndoChange, object: undoManager, queue: .main) { [weak self] _ in
                self?.undoJustPerformed = true
            }
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawingData.wrappedValue = canvasView.drawing.dataRepresentation()

            let strokes = canvasView.drawing.strokes
            let newCount = strokes.count
            let now = Date()

            if newCount > previousStrokeCount {
                if recentStrokeAddCount == 0 {
                    firstStrokeAddTime = now
                }
                recentStrokeAddCount += 1

                if recentStrokeAddCount >= scratchMinStrokes, let first = firstStrokeAddTime, now.timeIntervalSince(first) <= scratchTimeWindow {
                    onScratchDetected?()
                    recentStrokeAddCount = 0
                    firstStrokeAddTime = nil
                }
            } else if newCount < previousStrokeCount {
                recentStrokeAddCount = 0
                firstStrokeAddTime = nil
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if !self.undoJustPerformed {
                        self.onEraseStrokeComplete?()
                    }
                    self.undoJustPerformed = false
                }
            } else {
                recentStrokeAddCount = 0
                firstStrokeAddTime = nil
            }

            if let first = firstStrokeAddTime, now.timeIntervalSince(first) > scratchTimeWindow + 0.2 {
                recentStrokeAddCount = 0
                firstStrokeAddTime = nil
            }

            previousStrokeCount = newCount
        }

        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
            onPencilDoubleTap?()
        }
    }
}
