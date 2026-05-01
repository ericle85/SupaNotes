import PDFKit
import SwiftUI
import UIKit

// MARK: - Data Format

/// Entire drawing document for one page.
struct DrawingPage: Codable, Hashable {
    /// List of all strokes on the page.
    var strokes: [Stroke] = []
}

/// One drawn stroke: tool, color, thickness, and all points.
struct Stroke: Identifiable, Codable, Hashable {
    /// Unique identity for this stroke.
    let id: UUID
    /// Which tool created this stroke.
    let tool: DrawingTool
    /// Stroke color and width.
    let color: CodableColor
    let width: CGFloat
    /// Strokes are made up of a series of points.
    let points: [StrokePoint]
}

/// These are the stroke tools we support right now.
enum DrawingTool: String, Codable {
    /// Normal ink pen.
    case pen
}

/// A single 2D point for a stroke path, with optional pressure from Apple Pencil.
struct StrokePoint: Codable, Hashable {
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
enum DrawingCodec {
    /// Convert saved bytes into a document we can draw.
    static func decode(data: Data) -> DrawingPage {
        // If there is no data yet, return a brand-new empty drawing.
        guard !data.isEmpty else { return DrawingPage() }
        // Try to decode JSON; if decoding fails, return an empty drawing safely.
        return (try? JSONDecoder().decode(DrawingPage.self, from: data)) ?? DrawingPage()
    }

    /// Convert a drawing document into bytes so it can be saved.
    static func encode(currentPage: DrawingPage) -> Data {
        do {
            return try JSONEncoder().encode(currentPage)
        } catch {
            // Surface encoding failures during development so data-loss bugs are caught early.
            assertionFailure("Failed to encode drawing: \(error)")
            return Data()
        }
    }
}

// MARK: - Tool Style

/// Shared toolbar state (active tool, color, widths).
struct ToolStyle {
    /// Currently selected drawing tool.
    let selectedTool: ActiveTool
    /// Currently selected color.
    let selectedColor: Color
    /// Width for pen strokes.
    let penWidth: CGFloat
    /// Width for eraser.
    let eraserWidth: CGFloat

    /// Build this style from the shared toolbar state.
    static func from(toolbar: ToolbarState) -> ToolStyle {
        return ToolStyle(
            selectedTool: toolbar.currentlyActiveTool,
            selectedColor: toolbar.colorSelectedByUser,
            penWidth: toolbar.instrumentWidth(for: .pen),
            eraserWidth: toolbar.instrumentWidth(for: .eraser)
        )
    }
}

// MARK: - Interaction Callbacks

/// Callbacks to notify parent when drawing starts/ends.
protocol DrawingCanvasDelegate: AnyObject {
    /// Called when user starts using a tool on this page.
    func pageCanvasViewDidBeginUsingTool(_ view: DrawingCanvasView)
    /// Called when user stops using a tool on this page.
    func pageCanvasViewDidEndUsingTool(_ view: DrawingCanvasView)
}

// MARK: - Main Drawing View (Thin UI Shell)

/// Main drawing view for one page — delegates all stroke logic to StrokeEngine.
final class DrawingCanvasView: UIView, StrokeEngineDelegate {
    /// Constants for this canvas.
    private enum CanvasMetrics {
        /// Minimum and maximum render scales used for vector-quality redraws while zooming.
        static let renderScaleRange: ClosedRange<CGFloat> = 1 ... Design.Zoom.max
    }

    /// Delegate for interaction callbacks.
    weak var interactionDelegate: DrawingCanvasDelegate?

    /// The page model where drawing bytes are saved.
    private(set) var page: Page

    /// Pure-logic engine that owns stroke state, undo, eraser, and persistence.
    private let engine: StrokeEngine

    /// Low-level drawing surface that filters for pencil input.
    private let drawingView = PencilFilteredDrawingUIView()
    /// Vector PDF background that redraws at each zoom level.
    private let pdfBackgroundView = VectorPDFBackgroundView()
    /// Raster background for imported images.
    private let backgroundImageView = UIImageView()
    /// Current page zoom scale from the parent scroll view.
    private var zoomScale: CGFloat = 1

    /// Set up the view with page data and callbacks.
    init(page: Page, frame: CGRect, toolStyle: ToolStyle, onPageMutated: @escaping () -> Void) {
        self.page = page
        self.engine = StrokeEngine(page: page, toolStyle: toolStyle, onPageMutated: onPageMutated)
        super.init(frame: frame)
        // Wire engine delegate so we redraw on state changes.
        engine.delegate = self
        // Build the UI hierarchy.
        setupUI()
        // Sync initial engine state to drawing view.
        syncRenderState()
        // Apply template background.
        applyAppearance(for: page)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Expose the page-specific undo stack so toolbar undo/redo works.
    var undoManagerForPage: UndoManager {
        engine.undoManager
    }

    /// Update toolbar settings when they change.
    func updateToolStyle(_ style: ToolStyle) {
        engine.updateToolStyle(style)
    }

    /// Update render scale whenever the notebook zoom changes.
    func updateZoomScale(_ zoomScale: CGFloat) {
        // Clamp the zoom to the supported design range.
        self.zoomScale = min(max(zoomScale, Design.Zoom.min), Design.Zoom.max)
        // Ask the drawing surface to redraw vector strokes at a matching pixel scale.
        drawingView.updateRenderScale(
            forZoomScale: self.zoomScale,
            allowedRange: CanvasMetrics.renderScaleRange
        )
        // Re-render the PDF background at the new zoom so it stays sharp.
        pdfBackgroundView.updateRenderScale(
            forZoomScale: self.zoomScale,
            allowedRange: CanvasMetrics.renderScaleRange
        )
    }

    /// Force a save before export/print.
    func flushToModel() {
        engine.flush()
    }

    // MARK: StrokeEngineDelegate

    /// Called by the engine whenever visible state changes — sync to drawing view and redraw.
    func strokeEngineDidChangeRenderState(_ engine: StrokeEngine) {
        syncRenderState()
    }

    // MARK: Private

    /// Push current engine state into the drawing view and trigger a redraw.
    private func syncRenderState() {
        drawingView.currentPage = engine.currentPage
        drawingView.activeStroke = engine.activeStroke
        drawingView.eraserCursorCenter = engine.eraserCursorCenter
        drawingView.eraserCursorRadius = engine.eraserCursorRadius
        drawingView.setNeedsDisplay()
    }

    private func setupUI() {
        // Allow content to show outside bounds (for shadow effects).
        clipsToBounds = false

        // Vector PDF background — redraws sharply at any zoom level.
        pdfBackgroundView.contentMode = .redraw
        pdfBackgroundView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        pdfBackgroundView.frame = bounds
        addSubview(pdfBackgroundView)

        // Raster background for imported images.
        backgroundImageView.contentMode = .scaleToFill
        backgroundImageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backgroundImageView.frame = bounds
        addSubview(backgroundImageView)

        // Configure drawing surface with the page's coordinate space.
        drawingView.pageSize = page.size
        drawingView.backgroundColor = .clear
        // Redraw ink whenever geometry changes so vector strokes remain sharp.
        drawingView.contentMode = .redraw
        drawingView.translatesAutoresizingMaskIntoConstraints = false
        // Notify delegate when drawing starts.
        drawingView.onGestureBegan = { [weak self] in
            guard let self else { return }
            interactionDelegate?.pageCanvasViewDidBeginUsingTool(self)
        }
        // Forward pencil movement to the engine.
        drawingView.onChangedInLetterSpace = { [weak self] pointAndPressure in
            self?.engine.extendActiveStroke(at: pointAndPressure.0, pressure: pointAndPressure.1)
        }
        // Forward pencil lift to the engine, then notify delegate.
        drawingView.onEndedInLetterSpace = { [weak self] pointAndPressure in
            self?.engine.commitActiveStroke(at: pointAndPressure.0, pressure: pointAndPressure.1)
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
    }

    private func applyAppearance(for page: Page) {
        if let note = page.note, let pageNum = page.pdfPageNumber,
           let doc = PDFDocumentCache.document(for: note), let pdfPage = doc.page(at: pageNum)
        {
            // Vector PDF background — stays sharp at any zoom.
            pdfBackgroundView.pdfPage = pdfPage
            pdfBackgroundView.isHidden = false
            backgroundImageView.isHidden = true
            backgroundColor = .white
        } else if let imageData = page.backgroundImageData, let image = UIImage(data: imageData) {
            // Raster image background.
            pdfBackgroundView.isHidden = true
            backgroundImageView.image = image
            backgroundImageView.isHidden = false
            backgroundColor = .clear
        } else {
            // Plain template color.
            pdfBackgroundView.isHidden = true
            backgroundImageView.image = nil
            backgroundImageView.isHidden = true
            backgroundColor = page.template.backgroundColor
            overrideUserInterfaceStyle = page.template.interfaceStyle
        }
    }
}

// MARK: - Vector PDF Background

/// Draws a PDFPage via Core Graphics so it stays sharp at any zoom level.
private final class VectorPDFBackgroundView: UIView {
    /// The PDF page to render. Set to nil to clear.
    var pdfPage: PDFPage? {
        didSet { setNeedsDisplay() }
    }

    /// Current effective render scale, tracked to avoid redundant redraws.
    private var currentRenderScale: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Update pixel density to match zoom, same pattern as PencilFilteredDrawingUIView.
    func updateRenderScale(
        forZoomScale zoomScale: CGFloat,
        allowedRange: ClosedRange<CGFloat>
    ) {
        let screenScale = window?.windowScene?.screen.scale ?? traitCollection.displayScale
        let targetScale = min(max(screenScale * zoomScale, allowedRange.lowerBound), allowedRange.upperBound)
        guard abs(targetScale - currentRenderScale) > 0.01 else { return }
        currentRenderScale = targetScale
        contentScaleFactor = targetScale
        layer.contentsScale = targetScale
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let pdfPage, let ctx = UIGraphicsGetCurrentContext() else { return }
        let mediaBox = pdfPage.bounds(for: .mediaBox)
        // White background behind the PDF content.
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(rect)
        ctx.saveGState()
        // Flip coordinate system and scale PDF to fill the view bounds.
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: bounds.width / mediaBox.width, y: -bounds.height / mediaBox.height)
        pdfPage.draw(with: .mediaBox, to: ctx)
        ctx.restoreGState()
    }
}

// MARK: - Pencil-Only Drawing Surface

/// A drawing area that only responds to Apple Pencil, not finger touches.
/// This connects the drawing display with the pencil touch detection.
private final class PencilFilteredDrawingUIView: UIView {
    // The coordinate space for strokes, set from the page's dimensions.
    var pageSize = CGSize(width: PageConstants.pageWidth, height: PageConstants.pageHeight)

    /// All the drawings that have been saved.
    var currentPage = DrawingPage()
    /// The line currently being drawn before it's saved.
    var activeStroke: Stroke?
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
        updateRenderScale(forZoomScale: 1, allowedRange: 1 ... 6, preserveCurrentZoom: true)
    }

    /// Update the pixel density used to redraw vector strokes for the current zoom level.
    func updateRenderScale(
        forZoomScale zoomScale: CGFloat,
        allowedRange: ClosedRange<CGFloat>,
        preserveCurrentZoom: Bool = false
    ) {
        let screenScale = window?.windowScene?.screen.scale ?? traitCollection.displayScale
        let effectiveZoom = preserveCurrentZoom ? max(currentRenderScale / max(screenScale, 0.001), 1) : zoomScale
        let targetScale = min(max(screenScale * effectiveZoom, allowedRange.lowerBound), allowedRange.upperBound)
        guard abs(targetScale - currentRenderScale) > 0.01 else { return }
        currentRenderScale = targetScale
        contentScaleFactor = targetScale
        layer.contentsScale = targetScale
        setNeedsDisplay()
    }

    /// Only Apple Pencil touches are allowed — finger touches are ignored.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
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
            return self
        }
        guard !touches.isEmpty else { return self }
        return touches.contains { $0.type == .pencil || $0 == activePencilTouch } ? self : nil
    }

    /// Draw all the saved lines and the current line being drawn.
    override func draw(_: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        // Draw committed strokes via the shared renderer.
        StrokeRenderer.drawStrokes(from: currentPage, in: context, rect: bounds, pageSize: pageSize)

        // Draw the in-progress stroke on top (only exists during active touch).
        if let activeStroke {
            context.saveGState()
            context.scaleBy(x: bounds.width / pageSize.width, y: bounds.height / pageSize.height)
            StrokeRenderer.drawStroke(activeStroke, in: context)
            context.restoreGState()
        }

        // Draw eraser cursor circle while erasing.
        if let center = eraserCursorCenter {
            context.saveGState()
            let scaleX = bounds.width / pageSize.width
            let scaleY = bounds.height / pageSize.height
            let screenCenter = CGPoint(x: center.x * scaleX, y: center.y * scaleY)
            let screenRadius = eraserCursorRadius * scaleX
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
        guard activePencilTouch == nil else { return }
        guard let touch = touches.first(where: { $0.type == .pencil }) else { return }
        activePencilTouch = touch
        onGestureBegan?()
        let point = toLetterSpace(touch.location(in: self))
        let pressure: CGFloat = touch.force > 0 ? touch.force : 0.5
        onChangedInLetterSpace?((point, pressure))
    }

    /// Called when the pencil moves across the screen while drawing.
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard let activePencilTouch else { return }
        guard touches.contains(activePencilTouch) else { return }
        let location = activePencilTouch.location(in: self)
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
    private func toLetterSpace(_ point: CGPoint) -> CGPoint {
        PageLayout.toLetterSpace(point, viewSize: bounds.size, pageSize: pageSize)
    }
}
