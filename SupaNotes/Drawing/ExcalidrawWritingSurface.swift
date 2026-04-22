import SwiftUI
import UIKit

// MARK: - Saving and Loading Data

/// This helper turns raw bytes from the database into drawing objects, and back again.
private enum ExcalidrawCodec {
    /// Convert saved bytes into a document we can draw.
    static func decode(data: Data) -> ExcalidrawDocument {
        // If there is no data yet, return a brand-new empty drawing.
        guard !data.isEmpty else { return ExcalidrawDocument() }
        // Try to decode JSON; if decoding fails, return an empty drawing safely.
        return (try? JSONDecoder().decode(ExcalidrawDocument.self, from: data)) ?? ExcalidrawDocument()
    }

    /// Convert a drawing document into bytes so it can be saved.
    static func encode(document: ExcalidrawDocument) -> Data {
        // Try JSON encoding; if it fails, return empty data.
        (try? JSONEncoder().encode(document)) ?? Data()
    }
}

// MARK: - Drawing Tools

/// These are the stroke tools we support right now.
private enum ExcalidrawTool: String, Codable {
    /// Normal ink pen.
    case pen
    /// Transparent marker-like highlighter.
    case highlighter
}

// MARK: - Colors

/// A codable color model so we can save colors as plain numbers.
private struct ExcalidrawColor: Codable, Hashable {
    /// RBG channels, from 0 to 1.
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    /// Alpha (opacity), from 0 to 1.
    let alpha: CGFloat

    /// Build this model from a SwiftUI Color.
    init(color: Color) {
        // Convert SwiftUI Color to UIColor so we can read RGBA channels.
        let uiColor = UIColor(color)
        // Temporary storage for channel values.
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        // Ask UIColor for RGBA values.
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        // Save RBG channels.
        self.red = red
        self.green = green
        self.blue = blue
        // Save opacity channel.
        self.alpha = alpha
    }

    /// Convert saved RGBA values back to a SwiftUI Color.
    var swiftUIColor: Color {
        // Build the color from stored channels.
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}

// MARK: - Points and Coordinates

/// A single 2D point for a stroke path.
private struct ExcalidrawPoint: Codable, Hashable {
    /// XY coordinates.
    let pointX: CGFloat
    let pointY: CGFloat

    /// Convert this model to CoreGraphics point type.
    var cgPoint: CGPoint {
        // Build CGPoint from stored coordinates.
        CGPoint(x: pointX, y: pointY)
    }

    /// Create this model from a CoreGraphics point.
    init(_ point: CGPoint) {
        // Save XY coordinates.
        pointX = point.x
        pointY = point.y
    }
}

// MARK: - Drawing Strokes

/// One drawn stroke: tool, color, thickness, and all points.
private struct ExcalidrawStroke: Identifiable, Codable, Hashable {
    /// Unique identity for this stroke.
    let id: UUID
    /// Which tool created this stroke.
    let tool: ExcalidrawTool
    /// Stroke color and width.
    let color: ExcalidrawColor
    let width: CGFloat

    /// Strokes are made up of a series of points.
    let points: [ExcalidrawPoint]
}

// MARK: - The Drawing Page

/// Entire drawing document for one page.
private struct ExcalidrawDocument: Codable, Hashable {
    /// List of all strokes on the page.
    var strokes: [ExcalidrawStroke] = []
}

// MARK: - Undo and Redo

/// Tiny object we use as an UndoManager target.
private final class UndoBridge: NSObject {
    /// Closure that applies a restored document state.
    var apply: ((ExcalidrawDocument) -> Void)?
}

// MARK: - Main Drawing Screen

/// Main drawing view.
struct ExcalidrawWritingSurface: View {
    /// Constants for this canvas.
    private enum CanvasMetrics {
        /// US Letter in points (8.5 * 72 by 11 * 72).
        static let letterSize = CGSize(width: 612, height: 792)
    }

    /// The page model where drawing bytes are saved.
    let page: Page
    /// Shared toolbar state (active tool, color, widths).
    let toolbar: ToolbarState
    /// Undo manager from SwiftUI environment.
    var undoManager: UndoManager?
    /// Callback for parent to update modified time, etc.
    var onPageMutated: () -> Void

    /// Current in-memory drawing document.
    @State private var document = ExcalidrawDocument()
    /// Points currently being drawn before stroke is committed.
    @State private var activePoints: [CGPoint] = []
    /// Prevent loading from storage more than once.
    @State private var isLoaded = false
    /// Tracks stroke IDs erased in current eraser drag.
    @State private var erasingIDs = Set<UUID>()
    /// Snapshot before erasing starts, for undo.
    @State private var documentBeforeErasing = ExcalidrawDocument()
    /// Bridge object used by UndoManager.
    @State private var undoBridge = UndoBridge()

    // MARK: - What the Screen Looks Like

    /// SwiftUI view body.
    var body: some View {
        // Read the available screen size.
        GeometryReader { geometry in
            // Compute a centered letter-sized frame that fits this screen.
            let frame = letterFrame(in: geometry.size)

            // Stack background and page canvas.
            ZStack {
                // Light gray desk-like background around the page.
                Color(white: 0.95)
                    // Fill full screen.
                    .ignoresSafeArea()

                // Pencil-only drawing surface (render + input in one view).
                PencilFilteredDrawingSurface(
                    document: document,
                    activeStroke: activeStroke,
                    onChangedInLetterSpace: { point in
                        // Erase or draw depending on current tool.
                        if toolbar.currentlyActiveTool == .eraser {
                            handleEraserChanged(at: point)
                        } else {
                            handleDrawChanged(at: point)
                        }
                    },
                    onEndedInLetterSpace: { point in
                        // Finish erase or draw gesture depending on current tool.
                        if toolbar.currentlyActiveTool == .eraser {
                            handleEraserEnded(at: point)
                        } else {
                            handleDrawEnded(at: point)
                        }
                    }
                )
                // Set visible page size.
                .frame(width: frame.width, height: frame.height)
                // White paper background.
                .background(Color.white)
                // Slightly round paper corners.
                // .clipShape(RoundedRectangle(cornerRadius: 8))
                // Add subtle shadow so page looks elevated.
                .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
                // Place page at center of available area.
                .position(x: frame.midX, y: frame.midY)
            }
            // Allow gestures anywhere in this container.
            .contentShape(Rectangle())
        }
        // Load saved drawing data first time this view appears.
        .onAppear {
            // Only run once.
            guard !isLoaded else { return }
            // Mark as loaded.
            isLoaded = true
            // Read existing drawing bytes from page.
            document = ExcalidrawCodec.decode(data: page.drawingData)
            // Configure undo callback target.
            undoBridge.apply = { restored in
                // Apply restored document.
                document = restored
                // Save to page model.
                persist()
            }
        }
    }

    // MARK: - Touch and Drag Actions

    // MARK: - Current Drawing Info

    /// Temporary stroke used to preview current drag.
    private var activeStroke: ExcalidrawStroke? {
        // Need at least two points for a line preview.
        guard activePoints.count > 1 else { return nil }
        // Build preview stroke from active points.
        return ExcalidrawStroke(
            // Temporary ID.
            id: UUID(),
            // Active tool type.
            tool: activeTool,
            // Active color.
            color: ExcalidrawColor(color: toolbar.colorSelectedByUser),
            // Active line width.
            width: activeLineWidth,
            // Convert CGPoint list to codable point list.
            points: activePoints.map(ExcalidrawPoint.init)
        )
    }

    /// Convert toolbar active tool to drawing tool enum.
    private var activeTool: ExcalidrawTool {
        // Switch based on app toolbar state.
        switch toolbar.currentlyActiveTool {
        // Highlighter maps to highlighter.
        case .highlighter: .highlighter
        // Everything else maps to pen for now.
        default: .pen
        }
    }

    /// Current stroke width for drawing tools.
    private var activeLineWidth: CGFloat {
        // Decide width by active tool.
        switch toolbar.currentlyActiveTool {
        // Use highlighter width.
        case .highlighter:
            toolbar.instrumentWidth(for: .highlighter)
        // Default to pen width.
        default:
            toolbar.instrumentWidth(for: .pen)
        }
    }

    /// Current eraser radius/width from toolbar.
    private var eraserWidth: CGFloat {
        // Read eraser size configured in toolbar.
        toolbar.instrumentWidth(for: .eraser)
    }

    // MARK: - Drawing Actions

    /// Update in-progress draw points as drag moves.
    private func handleDrawChanged(at point: CGPoint) {
        // If this is first point, start the stroke.
        if activePoints.isEmpty {
            // Seed stroke with first point.
            activePoints = [point]
            // Exit after initialization.
            return
        }
        // Skip tiny moves to reduce noisy points.
        guard let last = activePoints.last, distance(last, point) >= 0.5 else {
            return
        }
        // Append new meaningful point.
        activePoints.append(point)
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
        }
        // Need at least one point to create a stroke (single-point stroke = dot).
        guard !activePoints.isEmpty else { return }

        // Capture previous state for undo.
        let previous = document
        // Append the new stroke.
        document.strokes.append(
            ExcalidrawStroke(
                // Real stroke ID.
                id: UUID(),
                // Tool used.
                tool: activeTool,
                // Color used.
                color: ExcalidrawColor(color: toolbar.colorSelectedByUser),
                // Width used.
                width: activeLineWidth,
                // Points used.
                points: activePoints.map(ExcalidrawPoint.init)
            )
        )
        // Register undo/redo for this stroke add.
        registerUndo(previous: previous, current: document, actionName: "Draw Stroke")
        // Persist to page model.
        persist()
    }

    // MARK: - Eraser Actions

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
            documentBeforeErasing = ExcalidrawDocument()
        }

        // If document did not change, skip undo/persist.
        guard documentBeforeErasing != document else { return }
        // Register undo/redo for erase operation.
        registerUndo(previous: documentBeforeErasing, current: document, actionName: "Erase Stroke")
        // Persist erased result.
        persist()
    }

    // MARK: - Saving and History

    /// Register one undo/redo pair.
    private func registerUndo(previous: ExcalidrawDocument, current: ExcalidrawDocument, actionName: String) {
        // If we do not have an undo manager, just skip.
        guard let undoManager else { return }
        // Register undo that restores previous state.
        undoManager.registerUndo(withTarget: undoBridge) { bridge in
            // Apply previous state.
            bridge.apply?(previous)
            // Register redo that restores current state again.
            undoManager.registerUndo(withTarget: bridge) { redoBridge in
                // Apply current state.
                redoBridge.apply?(current)
            }
        }
        // Give this undo item a readable name.
        undoManager.setActionName(actionName)
    }

    /// Save current document to the page model.
    private func persist() {
        // Encode drawing to bytes and assign to page.
        page.drawingData = ExcalidrawCodec.encode(document: document)
        // Notify parent that page changed.
        onPageMutated()
    }

    // MARK: - Math and Position Helpers

    /// True if any point in stroke is within eraser radius. We use this to determine if something is in the radius of our eraser.
    private func intersects(stroke: ExcalidrawStroke, point: CGPoint, radius: CGFloat) -> Bool {
        // Compare every stroke point to eraser center.
        stroke.points.contains { distance($0.cgPoint, point) <= radius }
    }

    /// Standard Euclidean distance between two points using hypotenuse formula.
    private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    /// Compute a centered letter frame that fits available size.
    private func letterFrame(in available: CGSize) -> CGRect {
        // Keep full page visible by taking smaller scale factor.
        let scale = min(available.width / CanvasMetrics.letterSize.width, available.height / CanvasMetrics.letterSize.height)
        // Actual on-screen page size after scaling.
        let size = CGSize(width: CanvasMetrics.letterSize.width * scale, height: CanvasMetrics.letterSize.height * scale)
        // Return centered frame.
        return CGRect(
            x: (available.width - size.width) * 0.5,
            y: (available.height - size.height) * 0.5,
            width: size.width,
            height: size.height
        )
    }
}

/// A drawing area that only responds to Apple Pencil, not finger touches.
/// This connects the drawing display with the pencil touch detection.
private struct PencilFilteredDrawingSurface: UIViewRepresentable {
    /// All the drawings that have been saved.
    let document: ExcalidrawDocument
    /// The line currently being drawn before it's saved.
    let activeStroke: ExcalidrawStroke?
    /// What to do when the pencil moves (updates the current line).
    let onChangedInLetterSpace: (CGPoint) -> Void
    /// What to do when the pencil stops drawing (saves the line).
    let onEndedInLetterSpace: (CGPoint) -> Void

    /// Create the actual drawing area on the screen.
    func makeUIView(context _: Context) -> PencilFilteredDrawingUIView {
        let view = PencilFilteredDrawingUIView()
        view.backgroundColor = .clear
        return view
    }

    /// Update the drawing area whenever the drawings change.
    func updateUIView(_ uiView: PencilFilteredDrawingUIView, context _: Context) {
        uiView.document = document
        uiView.activeStroke = activeStroke
        uiView.onChangedInLetterSpace = onChangedInLetterSpace
        uiView.onEndedInLetterSpace = onEndedInLetterSpace
        uiView.setNeedsDisplay()
    }
}

/// The actual drawing area that shows on screen.
/// It draws all the saved lines and only responds to Apple Pencil, not fingers.
private final class PencilFilteredDrawingUIView: UIView {
    /// The standard paper size (letter) used for storing drawings.
    private static let letterSize = CGSize(width: 612, height: 792)

    /// All the drawings that have been saved.
    var document = ExcalidrawDocument()
    /// The line currently being drawn before it's saved.
    var activeStroke: ExcalidrawStroke?
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

    /// This way of creating the view is not used in this app.
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Decide whether a touch should be recognized.
    /// Only Apple Pencil touches are allowed - finger touches are ignored.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // If the touch is outside the drawing area, ignore it.
        guard bounds.contains(point) else { return nil }
        guard let touches = event?.allTouches else {
            // Sometimes the system checks without telling us what touched.
            // We say yes to allow pencil touches to start.
            return self
        }
        guard !touches.isEmpty else { return self }
        // Only accept if there's an Apple Pencil touch.
        return touches.contains { touch in
            touch.type == .pencil || touch == activePencilTouch
        } ? self : nil
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
        let point = toLetterSpace(touch.location(in: self))
        onChangedInLetterSpace?(point)
    }

    /// Called when the pencil moves across the screen while drawing.
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        // Only respond if we're tracking a pencil touch.
        guard let activePencilTouch else { return }
        guard touches.contains(activePencilTouch) else { return }
        let point = toLetterSpace(activePencilTouch.location(in: self))
        onChangedInLetterSpace?(point)
    }

    /// Called when the pencil lifts off the screen.
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        // Only respond if we're tracking a pencil touch.
        guard let activePencilTouch else { return }
        guard touches.contains(activePencilTouch) else { return }
        let point = toLetterSpace(activePencilTouch.location(in: self))
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
        let point = toLetterSpace(activePencilTouch.location(in: self))
        onEndedInLetterSpace?(point)
        // Stop tracking this pencil touch.
        self.activePencilTouch = nil
    }

    /// Convert a screen position to a position on the standard paper size.
    /// This lets drawings look the same regardless of screen size.
    private func toLetterSpace(_ point: CGPoint) -> CGPoint {
        // Keep the point within the drawing area boundaries.
        let clampedX = max(0, min(bounds.width, point.x))
        let clampedY = max(0, min(bounds.height, point.y))
        // Convert to a percentage (0 to 1) of the screen size.
        let relativeX = bounds.width > 0 ? clampedX / bounds.width : 0
        let relativeY = bounds.height > 0 ? clampedY / bounds.height : 0
        // Apply that percentage to the standard paper size.
        return CGPoint(x: relativeX * Self.letterSize.width, y: relativeY * Self.letterSize.height)
    }

    /// Draw a single line on the screen.
    /// Makes smooth curves and handles both regular pens and highlighters.
    private func drawStroke(_ stroke: ExcalidrawStroke, in context: CGContext) {
        let points = stroke.points.map(\.cgPoint)
        guard !points.isEmpty else { return }

        // Set up how the line should look.
        let path = UIBezierPath()
        path.lineCapStyle = .round // Rounded line ends.
        path.lineJoinStyle = .round // Smooth line connections.
        path.lineWidth = stroke.width

        // If it's just a single dot, draw a circle.
        if points.count == 1 {
            let dotRect = CGRect(
                x: points[0].x - stroke.width * 0.5,
                y: points[0].y - stroke.width * 0.5,
                width: stroke.width,
                height: stroke.width
            )
            path.append(UIBezierPath(ovalIn: dotRect))
        } else {
            // Connect all the points with smooth curves.
            path.move(to: points[0])
            for index in 1 ..< points.count {
                let previous = points[index - 1]
                let current = points[index]
                // Find the middle point between two touches.
                let midpoint = CGPoint(x: (previous.x + current.x) * 0.5, y: (previous.y + current.y) * 0.5)
                if index == 1 {
                    path.addLine(to: midpoint)
                } else {
                    // Use a curve for smoother lines.
                    path.addQuadCurve(to: midpoint, controlPoint: previous)
                }
                if index == points.count - 1 {
                    path.addQuadCurve(to: current, controlPoint: current)
                }
            }
        }

        // Set the color.
        // Highlighters are semi-transparent so you can see through them.
        let baseColor = UIColor(stroke.color.swiftUIColor)
        let finalColor = stroke.tool == .highlighter ? baseColor.withAlphaComponent(0.35) : baseColor
        context.saveGState()
        // Highlighters blend with what's underneath like real highlighters.
        context.setBlendMode(stroke.tool == .highlighter ? .multiply : .normal)
        finalColor.setStroke()
        path.stroke()
        context.restoreGState()
    }
}
