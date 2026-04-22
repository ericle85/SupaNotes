import SwiftUI
import UIKit

// MARK: - Data Format

/// Entire drawing document for one page.
struct ExcalidrawPageDocument: Codable, Hashable {
    /// List of all strokes on the page.
    var strokes: [ExcalidrawPageStroke] = []
}

/// One drawn stroke: tool, color, thickness, and all points.
struct ExcalidrawPageStroke: Identifiable, Codable, Hashable {
    /// Unique identity for this stroke.
    let id: UUID
    /// Which tool created this stroke.
    let tool: ExcalidrawPageTool
    /// Stroke color and width.
    let color: CodableColor
    let width: CGFloat
    /// Strokes are made up of a series of points.
    let points: [ExcalidrawPagePoint]
}

/// These are the stroke tools we support right now.
enum ExcalidrawPageTool: String, Codable {
    /// Normal ink pen.
    case pen
    /// Transparent marker-like highlighter.
    case highlighter
}


/// A single 2D point for a stroke path.
struct ExcalidrawPagePoint: Codable, Hashable {
    /// XY coordinates.
    let pointX: CGFloat
    let pointY: CGFloat

    /// Create this model from a CoreGraphics point.
    nonisolated init(_ point: CGPoint) {
        // Save XY coordinates.
        pointX = point.x
        pointY = point.y
    }

    /// Convert this model to CoreGraphics point type.
    var cgPoint: CGPoint {
        // Build CGPoint from stored coordinates.
        CGPoint(x: pointX, y: pointY)
    }
}

/// This helper turns raw bytes from the database into drawing objects, and back again.
enum ExcalidrawPageCodec {
    /// Convert saved bytes into a document we can draw.
    static func decode(data: Data) -> ExcalidrawPageDocument {
        // If there is no data yet, return a brand-new empty drawing.
        guard !data.isEmpty else { return ExcalidrawPageDocument() }
        // Try to decode JSON; if decoding fails, return an empty drawing safely.
        return (try? JSONDecoder().decode(ExcalidrawPageDocument.self, from: data)) ?? ExcalidrawPageDocument()
    }

    /// Convert a drawing document into bytes so it can be saved.
    static func encode(document: ExcalidrawPageDocument) -> Data {
        // Try JSON encoding; if it fails, return empty data.
        (try? JSONEncoder().encode(document)) ?? Data()
    }
}

// MARK: - Tool Style

/// Shared toolbar state (active tool, color, widths).
struct ExcalidrawToolStyle {
    /// Currently selected drawing tool.
    let selectedTool: ActiveTool
    /// Currently selected color.
    let selectedColor: Color
    /// Width for pen strokes.
    let penWidth: CGFloat
    /// Width for highlighter strokes.
    let highlighterWidth: CGFloat
    /// Width for eraser.
    let eraserWidth: CGFloat

    /// Build this style from the shared toolbar state.
    static func from(toolbar: ToolbarState) -> ExcalidrawToolStyle {
        // Extract all toolbar settings into a simple struct.
        ExcalidrawToolStyle(
            selectedTool: toolbar.currentlyActiveTool,
            selectedColor: toolbar.colorSelectedByUser,
            penWidth: toolbar.instrumentWidth(for: .pen),
            highlighterWidth: toolbar.instrumentWidth(for: .highlighter),
            eraserWidth: toolbar.instrumentWidth(for: .eraser)
        )
    }
}

// MARK: - Interaction Callbacks

/// Callbacks to notify parent when drawing starts/ends.
protocol ExcalidrawPageCanvasInteractionDelegate: AnyObject {
    /// Called when user starts using a tool on this page.
    func pageCanvasViewDidBeginUsingTool(_ view: ExcalidrawPageCanvasView)
    /// Called when user stops using a tool on this page.
    func pageCanvasViewDidEndUsingTool(_ view: ExcalidrawPageCanvasView)
}

/// Tiny object we use as an UndoManager target.
private final class ExcalidrawUndoBridge: NSObject {
    /// Closure that applies a restored document state.
    var apply: ((ExcalidrawPageDocument) -> Void)?
}

// MARK: - Main Drawing Screen

/// Main drawing view for one page.
final class ExcalidrawPageCanvasView: UIView {
    /// Constants for this canvas.
    private enum CanvasMetrics {
        /// US Letter in points (8.5 * 72 by 11 * 72).
        static let letterSize = CGSize(width: PageConstants.pageWidth, height: PageConstants.pageHeight)
    }

    /// Delegate for interaction callbacks.
    weak var interactionDelegate: ExcalidrawPageCanvasInteractionDelegate?

    /// The page model where drawing bytes are saved.
    private(set) var page: Page
    /// Current in-memory drawing document.
    private var document = ExcalidrawPageDocument()
    /// Points currently being drawn before stroke is committed.
    private var activePoints: [CGPoint] = []
    /// Tracks stroke IDs erased in current eraser drag.
    private var erasingIDs = Set<UUID>()
    /// Snapshot before erasing starts, for undo.
    private var documentBeforeErasing = ExcalidrawPageDocument()

    /// Undo manager for this page.
    private let pageUndoManager = UndoManager()
    /// Bridge object used by UndoManager.
    private let undoBridge = ExcalidrawUndoBridge()

    /// Current toolbar settings.
    private var toolStyle: ExcalidrawToolStyle
    /// Low-level drawing surface that filters for pencil input.
    private let drawingView = PencilFilteredDrawingUIView()
    /// Background image view for PDF templates.
    private let backgroundImageView = UIImageView()
    /// Callback for parent to update modified time, etc.
    private var onPageMutated: () -> Void

    /// Set up the view with page data and callbacks.
    init(page: Page, frame: CGRect, toolStyle: ExcalidrawToolStyle, onPageMutated: @escaping () -> Void) {
        self.page = page
        self.toolStyle = toolStyle
        self.onPageMutated = onPageMutated
        super.init(frame: frame)
        // Build the UI hierarchy.
        setupUI()
        // Load existing drawing from storage.
        loadFromPage()
        // Apply template background.
        applyAppearance(for: page)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Expose the page-specific undo stack so toolbar undo/redo works.
    var undoManagerForPage: UndoManager {
        // Return the undo manager for this page.
        pageUndoManager
    }

    /// Update toolbar settings when they change.
    func updateToolStyle(_ style: ExcalidrawToolStyle) {
        // Save new toolbar settings.
        toolStyle = style
    }

    /// Force a save before export/print.
    func flushToModel() {
        // Write current document to page model.
        persist()
    }

    private func setupUI() {
        // Allow content to show outside bounds (for shadow effects).
        clipsToBounds = false

        // Configure background image view for PDF templates.
        backgroundImageView.contentMode = .scaleToFill
        backgroundImageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backgroundImageView.frame = bounds
        addSubview(backgroundImageView)

        // Configure drawing surface.
        drawingView.backgroundColor = .clear
        drawingView.translatesAutoresizingMaskIntoConstraints = false
        drawingView.document = document
        // Notify delegate when drawing starts.
        drawingView.onGestureBegan = { [weak self] in
            guard let self else { return }
            interactionDelegate?.pageCanvasViewDidBeginUsingTool(self)
        }
        // Handle pencil movement during drawing.
        drawingView.onChangedInLetterSpace = { [weak self] point in
            self?.handleChanged(at: point)
        }
        // Handle pencil lift at end of drawing.
        drawingView.onEndedInLetterSpace = { [weak self] point in
            self?.handleEnded(at: point)
            guard let self else { return }
            interactionDelegate?.pageCanvasViewDidEndUsingTool(self)
        }
        addSubview(drawingView)

        // Pin drawing view to fill entire area.
        NSLayoutConstraint.activate([
            drawingView.topAnchor.constraint(equalTo: topAnchor),
            drawingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            drawingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            drawingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Configure undo callback target.
        undoBridge.apply = { [weak self] restored in
            guard let self else { return }
            // Apply restored document.
            document = restored
            drawingView.document = restored
            drawingView.activeStroke = nil
            drawingView.setNeedsDisplay()
            // Save to page model.
            persist()
        }
    }

    private func loadFromPage() {
        // Read existing drawing bytes from page.
        document = ExcalidrawPageCodec.decode(data: page.drawingData)
        // Update drawing view with loaded document.
        drawingView.document = document
        // Trigger redraw.
        drawingView.setNeedsDisplay()
    }

    private func applyAppearance(for page: Page) {
        // If page has a PDF template, show it as background.
        if let image = PDFService.imageForPage(page) {
            backgroundImageView.image = image
            backgroundImageView.isHidden = false
            backgroundColor = .clear
        } else {
            // Otherwise use the template's solid color.
            backgroundImageView.image = nil
            backgroundImageView.isHidden = true
            backgroundColor = page.template.backgroundColor
            overrideUserInterfaceStyle = page.template.interfaceStyle
        }
    }

    /// Temporary stroke used to preview current drag.
    private var activeStrokePreview: ExcalidrawPageStroke? {
        // Need at least two points for a line preview.
        guard activePoints.count > 1 else { return nil }
        // Build preview stroke from active points.
        return ExcalidrawPageStroke(
            // Temporary ID.
            id: UUID(),
            // Active tool type.
            tool: activeStrokeTool,
            // Active color.
            color: CodableColor(color: toolStyle.selectedColor),
            // Active line width.
            width: activeLineWidth,
            // Convert CGPoint list to codable point list.
            points: activePoints.map(ExcalidrawPagePoint.init)
        )
    }

    /// Convert toolbar active tool to drawing tool enum.
    private var activeStrokeTool: ExcalidrawPageTool {
        // Switch based on app toolbar state.
        switch toolStyle.selectedTool {
        // Highlighter maps to highlighter.
        case .highlighter: .highlighter
        // Everything else maps to pen for now.
        default: .pen
        }
    }

    /// Current stroke width for drawing tools.
    private var activeLineWidth: CGFloat {
        // Decide width by active tool.
        switch toolStyle.selectedTool {
        // Use highlighter width.
        case .highlighter: toolStyle.highlighterWidth
        // Default to pen width.
        default: toolStyle.penWidth
        }
    }

    /// Current eraser radius/width from toolbar.
    private var eraserWidth: CGFloat {
        // Read eraser size configured in toolbar.
        toolStyle.eraserWidth
    }

    private func handleChanged(at point: CGPoint) {
        // Erase or draw depending on current tool.
        if toolStyle.selectedTool == .eraser {
            handleEraserChanged(at: point)
        } else {
            handleDrawChanged(at: point)
        }
    }

    private func handleEnded(at point: CGPoint) {
        // Finish erase or draw gesture depending on current tool.
        if toolStyle.selectedTool == .eraser {
            handleEraserEnded(at: point)
        } else {
            handleDrawEnded(at: point)
        }
    }

    /// Update in-progress draw points as drag moves.
    private func handleDrawChanged(at point: CGPoint) {
        // If this is first point, start the stroke.
        if activePoints.isEmpty {
            // Seed stroke with first point.
            activePoints = [point]
            drawingView.activeStroke = activeStrokePreview
            drawingView.setNeedsDisplay()
            return
        }
        // Skip tiny moves to reduce noisy points.
        guard let last = activePoints.last, distance(last, point) >= 0.5 else { return }
        // Append new meaningful point.
        activePoints.append(point)
        drawingView.activeStroke = activeStrokePreview
        drawingView.setNeedsDisplay()
    }

    /// Commit a stroke when drag ends.
    private func handleDrawEnded(at point: CGPoint) {
        // If somehow empty, create a starting point.
        if activePoints.isEmpty {
            // Seed point.
            activePoints = [point]
        } else if let last = activePoints.last, distance(last, point) > 0.5 {
            // Add final point if it is meaningfully different.
            activePoints.append(point)
        }

        // Always clear temporary points after this function exits.
        defer {
            activePoints = []
            drawingView.activeStroke = nil
            drawingView.setNeedsDisplay()
        }
        // Need at least one point to create a stroke (single-point stroke = dot).
        guard !activePoints.isEmpty else { return }

        // Capture previous state for undo.
        let previous = document
        // Append the new stroke.
        document.strokes.append(
            ExcalidrawPageStroke(
                // Real stroke ID.
                id: UUID(),
                // Tool used.
                tool: activeStrokeTool,
                // Color used.
                color: CodableColor(color: toolStyle.selectedColor),
                // Width used.
                width: activeLineWidth,
                // Points used.
                points: activePoints.map(ExcalidrawPagePoint.init)
            )
        )
        // Register undo/redo for this stroke add.
        registerUndo(previous: previous, current: document, actionName: "Draw Stroke")
        // Update drawing view.
        drawingView.document = document
        // Persist to page model.
        persist()
    }

    /// Eraser move handler.
    private func handleEraserChanged(at point: CGPoint) {
        // Snapshot original document at start of erase gesture.
        if erasingIDs.isEmpty {
            // Keep pre-erase copy for undo.
            documentBeforeErasing = document
        }

        // Use configured eraser width, with a tiny minimum.
        let radius = max(eraserWidth, 6)
        // Find stroke IDs that intersect current eraser point.
        let idsToErase = document.strokes
            .filter { !erasingIDs.contains($0.id) && intersects(stroke: $0, point: point, radius: radius) }
            .map(\.id)

        // If no intersections, nothing to remove.
        guard !idsToErase.isEmpty else { return }
        // Add intersected IDs to erase set.
        erasingIDs.formUnion(idsToErase)
        // Remove all erased strokes from document.
        document.strokes.removeAll { erasingIDs.contains($0.id) }
        drawingView.document = document
        drawingView.setNeedsDisplay()
    }

    /// Eraser end handler.
    private func handleEraserEnded(at point: CGPoint) {
        // Run one last intersection pass at gesture end point.
        handleEraserChanged(at: point)
        // Always clear temporary erase state after finishing.
        defer {
            // Clear tracked erased IDs.
            erasingIDs.removeAll()
            // Reset snapshot.
            documentBeforeErasing = ExcalidrawPageDocument()
        }

        // If document did not change, skip undo/persist.
        guard documentBeforeErasing != document else { return }
        // Register undo/redo for erase operation.
        registerUndo(previous: documentBeforeErasing, current: document, actionName: "Erase Stroke")
        // Persist erased result.
        persist()
    }

    /// Register one undo/redo pair.
    private func registerUndo(previous: ExcalidrawPageDocument, current: ExcalidrawPageDocument, actionName: String) {
        // Register undo that restores previous state.
        pageUndoManager.registerUndo(withTarget: undoBridge) { bridge in
            // Apply previous state.
            bridge.apply?(previous)
            // Register redo that restores current state again.
            self.pageUndoManager.registerUndo(withTarget: bridge) { redoBridge in
                // Apply current state.
                redoBridge.apply?(current)
            }
        }
        // Give this undo item a readable name.
        pageUndoManager.setActionName(actionName)
    }

    /// Save current document to the page model.
    private func persist() {
        // Encode drawing to bytes and assign to page.
        page.drawingData = ExcalidrawPageCodec.encode(document: document)
        // Notify parent that page changed.
        onPageMutated()
    }

    /// True if any point in the stroke is within eraser radius.
    /// We use this to determine whether a stroke should be erased.
    private func intersects(stroke: ExcalidrawPageStroke, point: CGPoint, radius: CGFloat) -> Bool {
        // Compare every stroke point to eraser center.
        stroke.points.contains { distance($0.cgPoint, point) <= radius }
    }

    /// Standard Euclidean distance between two points using hypotenuse formula.
    private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}

// MARK: - Pencil-Only Drawing Surface

/// A drawing area that only responds to Apple Pencil, not finger touches.
/// This connects the drawing display with the pencil touch detection.
private final class PencilFilteredDrawingUIView: UIView {
    /// The standard paper size (letter) used for storing drawings.
    private static let letterSize = CGSize(width: PageConstants.pageWidth, height: PageConstants.pageHeight)

    /// All the drawings that have been saved.
    var document = ExcalidrawPageDocument()
    /// The line currently being drawn before it's saved.
    var activeStroke: ExcalidrawPageStroke?
    /// What to do when the pencil first touches.
    var onGestureBegan: (() -> Void)?
    /// What to do when the pencil moves (updates the current line).
    var onChangedInLetterSpace: ((CGPoint) -> Void)?
    /// What to do when the pencil stops drawing (saves the line).
    var onEndedInLetterSpace: ((CGPoint) -> Void)?

    /// The pencil touch we're currently tracking.
    private var activePencilTouch: UITouch?
    /// Set up the drawing area when it's first created.
    /// Allow multiple touches to be detected (though only pencil will work).
    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Decide whether a touch should be recognized.
    /// Only Apple Pencil touches are allowed - finger touches are ignored.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // New touches must begin inside bounds.
        // But if we're already tracking a pencil touch, keep handling it even when
        // the contact drifts outside the canvas bounds.
        if !bounds.contains(point) {
            guard
                let activePencilTouch,
                event?.allTouches?.contains(activePencilTouch) == true
            else {
                return nil
            }
            return self
        }
        guard let touches = event?.allTouches else {
            // Sometimes the system checks without telling us what touched.
            // We say yes to allow pencil touches to start.
            return self
        }
        guard !touches.isEmpty else { return self }
        // Only accept if there's an Apple Pencil touch.
        return touches.contains { $0.type == .pencil || $0 == activePencilTouch } ? self : nil
    }

    /// Draw all the saved lines and the current line being drawn.
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        // Scale the drawing to fit the screen size.
        context.saveGState()
        context.scaleBy(x: rect.width / Self.letterSize.width, y: rect.height / Self.letterSize.height)
        // Draw each saved line.
        for stroke in document.strokes {
            drawStroke(stroke, in: context)
        }
        // Draw the line currently being drawn.
        if let activeStroke {
            drawStroke(activeStroke, in: context)
        }
        context.restoreGState()
    }

    /// Called when the pencil first touches the screen.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        // Only start if we're not already tracking a pencil touch.
        guard activePencilTouch == nil else { return }
        // Only respond to Apple Pencil, not fingers.
        guard let touch = touches.first(where: { $0.type == .pencil }) else { return }
        activePencilTouch = touch
        // Notify that gesture started.
        onGestureBegan?()
        // Report touch position in letter space.
        let point = toLetterSpace(touch.location(in: self))
        onChangedInLetterSpace?(point)
    }

    /// Called when the pencil moves across the screen while drawing.
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        // Only respond if we're tracking a pencil touch.
        guard let activePencilTouch else { return }
        guard touches.contains(activePencilTouch) else { return }
        let location = activePencilTouch.location(in: self)
        // Keep reporting points even when the pencil drifts off the page so the
        // saved path remains continuous and can reconnect naturally on re-entry.
        let point = toLetterSpace(location)
        onChangedInLetterSpace?(point)
    }

    /// Called when the pencil lifts off the screen.
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        // Only respond if we're tracking a pencil touch.
        guard let activePencilTouch else { return }
        guard touches.contains(activePencilTouch) else { return }
        let location = activePencilTouch.location(in: self)
        // Always end with the real final pencil position, including off-page, so
        // the committed stroke matches exactly what the user drew.
        let point = toLetterSpace(location)
        onEndedInLetterSpace?(point)
        // Stop tracking this pencil touch.
        self.activePencilTouch = nil
    }

    /// Called if the drawing is interrupted (like a phone call).
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        // Only respond if we're tracking a pencil touch.
        guard let activePencilTouch else { return }
        guard touches.contains(activePencilTouch) else { return }
        let location = activePencilTouch.location(in: self)
        // Mirror touchesEnded behavior so cancellation still commits the
        // continuous path that existed at interruption time.
        let point = toLetterSpace(location)
        onEndedInLetterSpace?(point)
        // Stop tracking this pencil touch.
        self.activePencilTouch = nil
    }

    /// Convert a screen position to a position on the standard paper size.
    /// This lets drawings look the same regardless of screen size.
    private func toLetterSpace(_ point: CGPoint) -> CGPoint {
        // Convert to a percentage (0 to 1) of the screen size.
        let relativeX = bounds.width > 0 ? point.x / bounds.width : 0
        let relativeY = bounds.height > 0 ? point.y / bounds.height : 0
        // Apply that percentage to the standard paper size.
        return CGPoint(x: relativeX * Self.letterSize.width, y: relativeY * Self.letterSize.height)
    }

    /// Draw a single line on the screen.
    /// Makes smooth curves and handles both regular pens and highlighters.
    private func drawStroke(_ stroke: ExcalidrawPageStroke, in context: CGContext) {
        let points = stroke.points.map(\.cgPoint)
        guard !points.isEmpty else { return }

        // Set the color.
        // Highlighters are semi-transparent so you can see through them.
        let baseColor = UIColor(stroke.color.toColor())
        let finalColor = stroke.tool == .highlighter ? baseColor.withAlphaComponent(0.35) : baseColor
        context.saveGState()
        // Highlighters blend with what's underneath like real highlighters.
        context.setBlendMode(stroke.tool == .highlighter ? .multiply : .normal)
        finalColor.setStroke()
        // Render the stroke as one continuous path, including off-page points.
        strokeSegment(points, strokeWidth: stroke.width)
        context.restoreGState()
    }

    /// Draw one continuous segment of a stroke.
    private func strokeSegment(_ points: [CGPoint], strokeWidth: CGFloat) {
        guard !points.isEmpty else { return }
        let path = UIBezierPath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.lineWidth = strokeWidth

        if points.count == 1 {
            // A single sampled point should render as a round dot whose diameter
            // matches the active stroke width, so taps still look like ink.
            let dotRect = CGRect(
                x: points[0].x - strokeWidth * 0.5,
                y: points[0].y - strokeWidth * 0.5,
                width: strokeWidth,
                height: strokeWidth
            )
            path.append(UIBezierPath(ovalIn: dotRect))
        } else if points.count == 2 {
            // For very short strokes, drawing a direct line is more predictable
            // than curve fitting and avoids introducing artificial bends.
            path.move(to: points[0])
            path.addLine(to: points[1])
        } else {
            // Use cubic Bézier segments generated from neighboring points so the
            // stroke passes through each sampled point with smoother transitions.
            path.move(to: points[0])
            for index in 0 ..< (points.count - 1) {
                // Collect the local neighborhood around this segment endpoint so
                // controls reflect both incoming and outgoing trajectory.
                let previousNeighbor = index > 0 ? points[index - 1] : points[index]
                let segmentStart = points[index]
                let segmentEnd = points[index + 1]
                let nextNeighbor = (index + 2) < points.count ? points[index + 2] : points[index + 1]

                // Convert Catmull-Rom style tangents into cubic Bézier control
                // points. This gives smooth joins without flattening segment ends.
                let controlPoint1 = CGPoint(
                    x: segmentStart.x + (segmentEnd.x - previousNeighbor.x) / 6,
                    y: segmentStart.y + (segmentEnd.y - previousNeighbor.y) / 6
                )
                let controlPoint2 = CGPoint(
                    x: segmentEnd.x - (nextNeighbor.x - segmentStart.x) / 6,
                    y: segmentEnd.y - (nextNeighbor.y - segmentStart.y) / 6
                )

                // Draw one cubic segment that ends exactly at the next sampled
                // point so the rendered ink follows the user's path.
                path.addCurve(to: segmentEnd, controlPoint1: controlPoint1, controlPoint2: controlPoint2)
            }
        }
        path.stroke()
    }
}
