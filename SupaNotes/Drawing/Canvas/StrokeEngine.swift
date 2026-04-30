import Foundation
import CoreGraphics

// MARK: - Delegate

/// Notifies the view layer when render state changes (document, active stroke, eraser cursor).
protocol StrokeEngineDelegate: AnyObject {
    /// Called whenever the engine's visible state changes and the view should redraw.
    func strokeEngineDidChangeRenderState(_ engine: StrokeEngine)
}

// MARK: - Undo Bridge

/// Tiny NSObject target for UndoManager registration (UndoManager requires an ObjC-compatible target).
private final class UndoBridge: NSObject {
    /// Closure that restores a document snapshot.
    var apply: ((ExcalidrawPageDocument) -> Void)?
}

// MARK: - Stroke Engine

/// Pure-logic engine that owns stroke accumulation, eraser hit-testing, undo/redo, and persistence.
/// No UIKit — the owning view reads published state and calls setNeedsDisplay.
final class StrokeEngine {

    // MARK: Delegate

    /// View that should redraw when state changes.
    weak var delegate: StrokeEngineDelegate?

    // MARK: Read-only render state

    /// Current committed strokes.
    private(set) var document: ExcalidrawPageDocument

    /// In-progress stroke preview (nil when not drawing).
    private(set) var activeStroke: ExcalidrawPageStroke?

    /// Center of the eraser cursor in page-space (nil when not erasing).
    private(set) var eraserCursorCenter: CGPoint?

    /// Radius of the eraser cursor in page-space points.
    private(set) var eraserCursorRadius: CGFloat = 0

    // MARK: Undo

    /// Page-scoped undo stack exposed so the toolbar can trigger undo/redo.
    let undoManager = UndoManager()

    // MARK: Private state

    /// Points + pressure collected during the current draw gesture.
    private var activePoints: [(point: CGPoint, pressure: CGFloat)] = []

    /// Stroke IDs removed during the current eraser drag.
    private var erasingIDs = Set<UUID>()

    /// Document snapshot taken at the start of an erase gesture (for undo).
    private var documentBeforeErasing = ExcalidrawPageDocument()

    /// Current toolbar settings (tool, color, widths).
    private var toolStyle: ExcalidrawToolStyle

    /// Page model reference for persistence.
    private let page: Page

    /// Parent callback invoked after every persist.
    private let onPageMutated: () -> Void

    /// Bridge object that UndoManager targets.
    private let undoBridge = UndoBridge()

    // MARK: Init

    /// Create an engine for a given page, loading any existing drawing data.
    init(page: Page, toolStyle: ExcalidrawToolStyle, onPageMutated: @escaping () -> Void) {
        self.page = page
        self.toolStyle = toolStyle
        self.onPageMutated = onPageMutated
        // Decode persisted drawing (empty document if no data yet).
        self.document = ExcalidrawPageCodec.decode(data: page.drawingData)

        // Wire up the undo bridge to restore snapshots through the engine.
        undoBridge.apply = { [weak self] restored in
            guard let self else { return }
            document = restored
            activeStroke = nil
            persist()
            delegate?.strokeEngineDidChangeRenderState(self)
        }
    }

    // MARK: Tool style

    /// Update toolbar settings when the user changes tool/color/width.
    func updateToolStyle(_ style: ExcalidrawToolStyle) {
        toolStyle = style
    }

    // MARK: Touch dispatch

    /// Route a moved-touch to the correct handler based on active tool.
    func handleChanged(at point: CGPoint, pressure: CGFloat) {
        if toolStyle.selectedTool == .eraser {
            handleEraserChanged(at: point)
        } else {
            handleDrawChanged(at: point, pressure: pressure)
        }
    }

    /// Route a ended-touch to the correct handler based on active tool.
    func handleEnded(at point: CGPoint, pressure: CGFloat) {
        if toolStyle.selectedTool == .eraser {
            handleEraserEnded(at: point)
        } else {
            handleDrawEnded(at: point, pressure: pressure)
        }
    }

    // MARK: Persistence

    /// Force a save (e.g. before export/print).
    func flush() {
        persist()
    }

    // MARK: - Drawing

    /// Accumulate points during a draw gesture and update the live preview.
    private func handleDrawChanged(at point: CGPoint, pressure: CGFloat) {
        if activePoints.isEmpty {
            activePoints = [(point, pressure)]
            activeStroke = buildActiveStrokePreview()
            delegate?.strokeEngineDidChangeRenderState(self)
            return
        }
        // Skip tiny moves to reduce noisy points.
        guard let last = activePoints.last, distance(last.point, point) >= 0.5 else { return }
        activePoints.append((point, pressure))
        activeStroke = buildActiveStrokePreview()
        delegate?.strokeEngineDidChangeRenderState(self)
    }

    /// Commit the completed stroke to the document.
    private func handleDrawEnded(at point: CGPoint, pressure: CGFloat) {
        // Append final point if meaningful.
        if activePoints.isEmpty {
            activePoints = [(point, pressure)]
        } else if let last = activePoints.last, distance(last.point, point) > 0.5 {
            activePoints.append((point, pressure))
        }

        defer {
            activePoints = []
            activeStroke = nil
            delegate?.strokeEngineDidChangeRenderState(self)
        }
        guard !activePoints.isEmpty else { return }

        // Snapshot for undo, then append new stroke.
        let previous = document
        let newStroke = ExcalidrawPageStroke(
            id: UUID(),
            tool: .pen,
            color: CodableColor(color: toolStyle.selectedColor),
            width: toolStyle.penWidth,
            points: activePoints.map { ExcalidrawPagePoint($0.point, pressure: $0.pressure) }
        )
        document.strokes.append(newStroke)
        registerUndo(previous: previous, current: document, actionName: "Draw Stroke")
        persist()
    }

    // MARK: - Erasing

    /// Remove strokes that intersect the eraser cursor as it moves.
    private func handleEraserChanged(at point: CGPoint) {
        // Snapshot at the start of the erase gesture.
        if erasingIDs.isEmpty {
            documentBeforeErasing = document
        }

        let radius = max(toolStyle.eraserWidth, 6)
        eraserCursorCenter = point
        eraserCursorRadius = radius

        // Find strokes that intersect the eraser circle.
        let hitIDs = document.strokes
            .filter { !erasingIDs.contains($0.id) && intersects(stroke: $0, point: point, radius: radius) }
            .map(\.id)

        if hitIDs.isEmpty {
            // Still notify so cursor position updates on screen.
            delegate?.strokeEngineDidChangeRenderState(self)
            return
        }

        erasingIDs.formUnion(hitIDs)
        document.strokes.removeAll { erasingIDs.contains($0.id) }
        delegate?.strokeEngineDidChangeRenderState(self)
    }

    /// Finish the erase gesture and register undo if anything was removed.
    private func handleEraserEnded(at point: CGPoint) {
        // One last intersection pass at the lift-off point.
        handleEraserChanged(at: point)
        // Hide cursor.
        eraserCursorCenter = nil
        delegate?.strokeEngineDidChangeRenderState(self)

        defer {
            erasingIDs.removeAll()
            documentBeforeErasing = ExcalidrawPageDocument()
        }

        // Skip undo/persist if nothing changed.
        guard documentBeforeErasing != document else { return }
        registerUndo(previous: documentBeforeErasing, current: document, actionName: "Erase Stroke")
        persist()
    }

    // MARK: - Helpers

    /// Build a temporary stroke from the points collected so far (for live preview).
    private func buildActiveStrokePreview() -> ExcalidrawPageStroke? {
        guard activePoints.count > 1 else { return nil }
        return ExcalidrawPageStroke(
            id: UUID(),
            tool: .pen,
            color: CodableColor(color: toolStyle.selectedColor),
            width: toolStyle.penWidth,
            points: activePoints.map { ExcalidrawPagePoint($0.point, pressure: $0.pressure) }
        )
    }

    /// Register a symmetric undo/redo pair for a document state change.
    /// Each side re-registers the opposite so undo/redo can loop indefinitely.
    private func registerUndo(previous: ExcalidrawPageDocument, current: ExcalidrawPageDocument, actionName: String) {
        undoManager.registerUndo(withTarget: undoBridge) { [weak self] bridge in
            bridge.apply?(previous)
            self?.registerUndo(previous: current, current: previous, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }

    /// Encode document to bytes and write to the page model.
    private func persist() {
        page.drawingData = ExcalidrawPageCodec.encode(document: document)
        onPageMutated()
    }

    /// True if any point in the stroke falls within the eraser radius.
    private func intersects(stroke: ExcalidrawPageStroke, point: CGPoint, radius: CGFloat) -> Bool {
        stroke.points.contains { distance($0.cgPoint, point) <= radius }
    }

    /// Euclidean distance between two points.
    private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}
