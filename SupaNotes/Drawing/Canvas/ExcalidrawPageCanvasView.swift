import SwiftUI
import UIKit

// MARK: - Data Format

/// Entire drawing document for one page.
struct ExcalidrawPageDocument: Codable, Hashable {
    /// List of all strokes on the page.
    var strokes: [ExcalidrawPageStroke] = []
}

/// One drawn stroke: tool, color, thickness, pen style metadata, and all points.
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
    /// Pen style used when drawing (nil for legacy strokes).
    let penStyle: PenStyle?
    /// Tip sharpness at time of drawing (nil for legacy strokes).
    let tipSharpness: CGFloat?
    /// Pressure sensitivity at time of drawing (nil for legacy strokes).
    let pressureSensitivity: CGFloat?
}

/// These are the stroke tools we support right now.
enum ExcalidrawPageTool: String, Codable {
    /// Normal ink pen.
    case pen
}

/// A single 2D point for a stroke path, with optional pressure from Apple Pencil.
struct ExcalidrawPagePoint: Codable, Hashable {
    /// XY coordinates.
    let pointX: CGFloat
    let pointY: CGFloat
    /// Apple Pencil pressure at this point (nil for legacy strokes).
    let pressure: CGFloat?

    /// Create this model from a CoreGraphics point and pressure value.
    nonisolated init(_ point: CGPoint, pressure: CGFloat? = nil) {
        pointX = point.x
        pointY = point.y
        self.pressure = pressure
    }

    /// Convert this model to CoreGraphics point type.
    var cgPoint: CGPoint {
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
        do {
            return try JSONEncoder().encode(document)
        } catch {
            // Surface encoding failures during development so data-loss bugs are caught early.
            assertionFailure("Failed to encode drawing: \(error)")
            return Data()
        }
    }
}

// MARK: - Tool Style

/// Shared toolbar state (active tool, color, widths, pen settings).
struct ExcalidrawToolStyle {
    /// Currently selected drawing tool.
    let selectedTool: ActiveTool
    /// Currently selected color.
    let selectedColor: Color
    /// Width for pen strokes.
    let penWidth: CGFloat
    /// Width for eraser.
    let eraserWidth: CGFloat
    /// Pen rendering style (fountain, ballpoint, brush).
    let penStyle: PenStyle
    /// How thin the stroke tapers at low pressure.
    let tipSharpness: CGFloat
    /// How much pencil pressure affects stroke width.
    let pressureSensitivity: CGFloat

    /// Build this style from the shared toolbar state.
    static func from(toolbar: ToolbarState) -> ExcalidrawToolStyle {
        // Read pen-specific settings from the pen icon's instrument settings.
        let penSettings = toolbar.toolbarIcons
            .first(where: { $0.type == .pen })?.instrumentSettings ?? .pen()
        return ExcalidrawToolStyle(
            selectedTool: toolbar.currentlyActiveTool,
            selectedColor: toolbar.colorSelectedByUser,
            penWidth: toolbar.instrumentWidth(for: .pen),
            eraserWidth: toolbar.instrumentWidth(for: .eraser),
            penStyle: penSettings.penStyle,
            tipSharpness: penSettings.tipSharpness,
            pressureSensitivity: penSettings.pressureSensitivity
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
        /// Minimum and maximum render scales used for vector-quality redraws while zooming.
        /// Matches the design zoom max to ensure strokes stay sharp at all supported zoom levels.
        static let renderScaleRange: ClosedRange<CGFloat> = 1 ... Design.Zoom.max
    }

    /// Delegate for interaction callbacks.
    weak var interactionDelegate: ExcalidrawPageCanvasInteractionDelegate?

    /// The page model where drawing bytes are saved.
    private(set) var page: Page
    /// Current in-memory drawing document.
    private var document = ExcalidrawPageDocument()
    /// Points + pressure currently being drawn before stroke is committed.
    private var activePoints: [(point: CGPoint, pressure: CGFloat)] = []
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
    /// Current page zoom scale from the parent scroll view.
    private var zoomScale: CGFloat = 1

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

    /// Update render scale whenever the notebook zoom changes.
    func updateZoomScale(_ zoomScale: CGFloat) {
        // Clamp the zoom to the supported design range so accidental values do not destabilize rendering.
        self.zoomScale = min(max(zoomScale, Design.Zoom.min), Design.Zoom.max)
        // Ask the drawing surface to redraw vector strokes at a matching pixel scale.
        drawingView.updateRenderScale(
            forZoomScale: self.zoomScale,
            allowedRange: CanvasMetrics.renderScaleRange
        )
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
        // Redraw ink whenever geometry changes so vector strokes remain sharp.
        drawingView.contentMode = .redraw
        drawingView.translatesAutoresizingMaskIntoConstraints = false
        drawingView.document = document
        // Notify delegate when drawing starts.
        drawingView.onGestureBegan = { [weak self] in
            guard let self else { return }
            interactionDelegate?.pageCanvasViewDidBeginUsingTool(self)
        }
        // Handle pencil movement during drawing (point + pressure).
        drawingView.onChangedInLetterSpace = { [weak self] pointAndPressure in
            self?.handleChanged(at: pointAndPressure.0, pressure: pointAndPressure.1)
        }
        // Handle pencil lift at end of drawing (point + pressure).
        drawingView.onEndedInLetterSpace = { [weak self] pointAndPressure in
            self?.handleEnded(at: pointAndPressure.0, pressure: pointAndPressure.1)
            guard let self else { return }
            interactionDelegate?.pageCanvasViewDidEndUsingTool(self)
        }
        addSubview(drawingView)

        // Pin drawing view to fill entire area.
        NSLayoutConstraint.activate([
            drawingView.topAnchor.constraint(equalTo: topAnchor),
            drawingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            drawingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            drawingView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Configure initial render scale before the first draw call.
        updateZoomScale(zoomScale)

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
        guard activePoints.count > 1 else { return nil }
        return ExcalidrawPageStroke(
            id: UUID(),
            tool: activeStrokeTool,
            color: CodableColor(color: toolStyle.selectedColor),
            width: activeLineWidth,
            points: activePoints.map { ExcalidrawPagePoint($0.point, pressure: $0.pressure) },
            penStyle: toolStyle.penStyle,
            tipSharpness: toolStyle.tipSharpness,
            pressureSensitivity: toolStyle.pressureSensitivity
        )
    }

    /// Convert toolbar active tool to drawing tool enum.
    private var activeStrokeTool: ExcalidrawPageTool {
        // Only pen strokes are supported.
        .pen
    }

    /// Current stroke width for drawing tools.
    private var activeLineWidth: CGFloat {
        // Only pen width is used.
        toolStyle.penWidth
    }

    /// Current eraser radius/width from toolbar.
    private var eraserWidth: CGFloat {
        // Read eraser size configured in toolbar.
        toolStyle.eraserWidth
    }

    private func handleChanged(at point: CGPoint, pressure: CGFloat) {
        if toolStyle.selectedTool == .eraser {
            handleEraserChanged(at: point)
        } else {
            handleDrawChanged(at: point, pressure: pressure)
        }
    }

    private func handleEnded(at point: CGPoint, pressure: CGFloat) {
        if toolStyle.selectedTool == .eraser {
            handleEraserEnded(at: point)
        } else {
            handleDrawEnded(at: point, pressure: pressure)
        }
    }

    /// Update in-progress draw points as drag moves.
    private func handleDrawChanged(at point: CGPoint, pressure: CGFloat) {
        if activePoints.isEmpty {
            activePoints = [(point, pressure)]
            drawingView.activeStroke = activeStrokePreview
            drawingView.setNeedsDisplay()
            return
        }
        // Skip tiny moves to reduce noisy points.
        guard let last = activePoints.last, distance(last.point, point) >= 0.5 else { return }
        activePoints.append((point, pressure))
        drawingView.activeStroke = activeStrokePreview
        drawingView.setNeedsDisplay()
    }

    /// Commit a stroke when drag ends.
    private func handleDrawEnded(at point: CGPoint, pressure: CGFloat) {
        if activePoints.isEmpty {
            activePoints = [(point, pressure)]
        } else if let last = activePoints.last, distance(last.point, point) > 0.5 {
            activePoints.append((point, pressure))
        }

        defer {
            activePoints = []
            drawingView.activeStroke = nil
            drawingView.setNeedsDisplay()
        }
        guard !activePoints.isEmpty else { return }

        let previous = document
        document.strokes.append(
            ExcalidrawPageStroke(
                id: UUID(),
                tool: activeStrokeTool,
                color: CodableColor(color: toolStyle.selectedColor),
                width: activeLineWidth,
                points: activePoints.map { ExcalidrawPagePoint($0.point, pressure: $0.pressure) },
                penStyle: toolStyle.penStyle,
                tipSharpness: toolStyle.tipSharpness,
                pressureSensitivity: toolStyle.pressureSensitivity
            )
        )
        registerUndo(previous: previous, current: document, actionName: "Draw Stroke")
        drawingView.document = document
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

        // Update the eraser cursor circle so the user sees the erase area.
        drawingView.eraserCursorCenter = point
        drawingView.eraserCursorRadius = radius

        // Find stroke IDs that intersect current eraser point.
        let idsToErase = document.strokes
            .filter { !erasingIDs.contains($0.id) && intersects(stroke: $0, point: point, radius: radius) }
            .map(\.id)

        // Update display even when nothing is erased (cursor still moves).
        if idsToErase.isEmpty {
            drawingView.setNeedsDisplay()
            return
        }
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
        // Hide the eraser cursor circle now that the gesture is done.
        drawingView.eraserCursorCenter = nil
        drawingView.setNeedsDisplay()
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
        pageUndoManager.registerUndo(withTarget: undoBridge) { [weak self] bridge in
            // Apply previous state.
            bridge.apply?(previous)
            // Register redo that restores current state again.
            self?.pageUndoManager.registerUndo(withTarget: bridge) { redoBridge in
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
    /// Center of the eraser cursor circle in letter space (nil when not erasing).
    var eraserCursorCenter: CGPoint?
    /// Radius of the eraser cursor in letter-space points.
    var eraserCursorRadius: CGFloat = 0
    /// What to do when the pencil first touches.
    var onGestureBegan: (() -> Void)?
    /// What to do when the pencil moves (point in letter space + pressure).
    var onChangedInLetterSpace: (((CGPoint, CGFloat)) -> Void)?
    /// What to do when the pencil stops drawing (point in letter space + pressure).
    var onEndedInLetterSpace: (((CGPoint, CGFloat)) -> Void)?

    /// The pencil touch we're currently tracking.
    private var activePencilTouch: UITouch?
    /// Last effective pixel scale used for redraw so we avoid redundant invalidations.
    private var currentRenderScale: CGFloat = 0

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

    /// Re-apply screen-aware scale whenever this view moves to a new window/screen.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Keep current zoom assumption but refresh against the active screen scale.
        updateRenderScale(forZoomScale: 1, allowedRange: 1 ... 6, preserveCurrentZoom: true)
    }

    /// Update the pixel density used to redraw vector strokes for the current zoom level.
    func updateRenderScale(
        forZoomScale zoomScale: CGFloat,
        allowedRange: ClosedRange<CGFloat>,
        preserveCurrentZoom: Bool = false
    ) {
        // Use active window scale when available (important for external displays), else fall back to main screen.
        let screenScale = window?.windowScene?.screen.scale ?? traitCollection.displayScale
        // Derive target pixels-per-point so strokes stay sharp as the user zooms in.
        let effectiveZoom = preserveCurrentZoom ? max(currentRenderScale / max(screenScale, 0.001), 1) : zoomScale
        let targetScale = min(max(screenScale * effectiveZoom, allowedRange.lowerBound), allowedRange.upperBound)
        // Avoid expensive redraw churn when scale change is visually insignificant.
        guard abs(targetScale - currentRenderScale) > 0.01 else { return }
        // Store and apply the new drawing scale for both UIView and tiled backing layer.
        currentRenderScale = targetScale
        contentScaleFactor = targetScale
        layer.contentsScale = targetScale
        // Trigger redraw so tiles regenerate at the new detail level.
        setNeedsDisplay()
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
    override func draw(_: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        // Draw committed strokes via the shared renderer.
        StrokeRenderer.drawStrokes(from: document, in: context, rect: bounds)

        // Draw the in-progress stroke on top (only exists during active touch).
        if let activeStroke {
            context.saveGState()
            context.scaleBy(x: bounds.width / Self.letterSize.width, y: bounds.height / Self.letterSize.height)
            StrokeRenderer.drawStroke(activeStroke, in: context)
            context.restoreGState()
        }

        // Draw eraser cursor circle while erasing.
        if let center = eraserCursorCenter {
            context.saveGState()
            // Scale from letter space to screen space.
            let scaleX = bounds.width / Self.letterSize.width
            let scaleY = bounds.height / Self.letterSize.height
            let screenCenter = CGPoint(x: center.x * scaleX, y: center.y * scaleY)
            let screenRadius = eraserCursorRadius * scaleX
            // Semi-transparent fill with a visible border.
            context.setFillColor(UIColor.systemGray.withAlphaComponent(0.15).cgColor)
            context.setStrokeColor(UIColor.systemGray.withAlphaComponent(0.5).cgColor)
            context.setLineWidth(1.5)
            let rect = CGRect(
                x: screenCenter.x - screenRadius,
                y: screenCenter.y - screenRadius,
                width: screenRadius * 2,
                height: screenRadius * 2
            )
            context.addEllipse(in: rect)
            context.drawPath(using: .fillStroke)
            context.restoreGState()
        }
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
        // Report touch position in letter space. Force is 0 at first contact
        // (digitizer hasn't sampled yet), so use a neutral fallback.
        let point = toLetterSpace(touch.location(in: self))
        let pressure: CGFloat = touch.force > 0 ? touch.force : 0.5
        onChangedInLetterSpace?((point, pressure))
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
        onChangedInLetterSpace?((point, activePencilTouch.force))
    }

    /// Called when the pencil lifts off the screen.
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        guard let activePencilTouch else { return }
        guard touches.contains(activePencilTouch) else { return }
        let location = activePencilTouch.location(in: self)
        let point = toLetterSpace(location)
        // Pencil force at lift-off is typically 0; pass it through for consistency.
        onEndedInLetterSpace?((point, activePencilTouch.force))
        self.activePencilTouch = nil
    }

    /// Called if the drawing is interrupted (like a phone call).
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        guard let activePencilTouch else { return }
        guard touches.contains(activePencilTouch) else { return }
        let location = activePencilTouch.location(in: self)
        let point = toLetterSpace(location)
        onEndedInLetterSpace?((point, activePencilTouch.force))
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

}
