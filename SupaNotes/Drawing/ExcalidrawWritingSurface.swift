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

                // SwiftUI immediate-mode drawing surface.
                Canvas { context, _ in
                    // Scale drawing commands from letter-space to visible frame.
                    context.scaleBy(
                        x: frame.width / CanvasMetrics.letterSize.width,
                        y: frame.height / CanvasMetrics.letterSize.height
                    )
                    // Draw every saved stroke.
                    for stroke in document.strokes {
                        // Render one stroke.
                        draw(stroke: stroke, in: &context)
                    }
                    // Draw in-progress stroke while user is dragging.
                    if let activeStroke {
                        // Render temporary stroke preview.
                        draw(stroke: activeStroke, in: &context)
                    }
                }
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
            // Attach draw/erase drag gesture.
            .gesture(writingGesture(frame: frame))
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

    /// Drag gesture used for drawing and erasing.
    private func writingGesture(frame: CGRect) -> some Gesture {
        // Minimum distance 0 means immediate touch-down response.
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            // Called while finger/pencil moves.
            .onChanged { value in
                // Ignore touches outside the letter page.
                guard let point = toCanvasPoint(value.location, frame: frame) else {
                    // Exit early when outside page.
                    return
                }
                // Route to eraser logic if eraser is active.
                if toolbar.currentlyActiveTool == .eraser {
                    // Update erasing operation.
                    handleEraserChanged(at: point)
                } else {
                    // Update drawing operation.
                    handleDrawChanged(at: point)
                }
            }
            // Called once when drag ends.
            .onEnded { value in
                // Ignore ended touches outside letter page.
                guard let point = toCanvasPoint(value.location, frame: frame) else {
                    // Clear in-progress draw points.
                    activePoints = []
                    // Clear erasing set.
                    erasingIDs.removeAll()
                    // Reset erasing snapshot.
                    documentBeforeErasing = ExcalidrawDocument()
                    // Exit early.
                    return
                }
                // Route to eraser finish if eraser is active.
                if toolbar.currentlyActiveTool == .eraser {
                    // Finish erase gesture.
                    handleEraserEnded(at: point)
                } else {
                    // Finish draw gesture.
                    handleDrawEnded(at: point)
                }
            }
    }

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
        guard let last = activePoints.last, distance(last, point) >= 0.5 else { return }
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
        defer { activePoints = [] }
        // Need enough points to create a stroke.
        guard activePoints.count > 1 else { return }

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

    // MARK: - Drawing on Screen

    /// Draw one stroke onto the Canvas context.
    private func draw(stroke: ExcalidrawStroke, in context: inout GraphicsContext) {
        // Convert model points to CG points.
        let points = stroke.points.map(\.cgPoint)
        // If no points, there is nothing to draw.
        guard !points.isEmpty else { return }

        // Build a path for this stroke.
        var path = Path()
        // If exactly one point, draw a dot.
        if points.count == 1 {
            // Dot is represented as a small circle.
            path.addEllipse(in: CGRect(
                x: points[0].x - stroke.width * 0.5,
                y: points[0].y - stroke.width * 0.5,
                width: stroke.width,
                height: stroke.width
            ))
        } else {
            // Start at first point.
            path.move(to: points[0])
            // Walk through remaining points and smooth with quadratic curves.
            for index in 1 ..< points.count {
                // Previous point.
                let previous = points[index - 1]
                // Current point.
                let current = points[index]
                // Midpoint helps smooth transitions.
                let midpoint = CGPoint(x: (previous.x + current.x) * 0.5, y: (previous.y + current.y) * 0.5)
                // For first segment, draw a line to midpoint.
                if index == 1 {
                    path.addLine(to: midpoint)
                } else {
                    // For others, draw curve using previous as control point.
                    path.addQuadCurve(to: midpoint, control: previous)
                }
                // Finish by curving to the final point.
                if index == points.count - 1 {
                    path.addQuadCurve(to: current, control: current)
                }
            }
        }

        // Highlighter uses lower opacity; pen uses full opacity.
        let color = stroke.tool == .highlighter
            ? stroke.color.swiftUIColor.opacity(0.35)
            : stroke.color.swiftUIColor
        // Highlighter blends with multiply for marker-like feel.
        let blend: GraphicsContext.BlendMode = stroke.tool == .highlighter ? .multiply : .normal
        // Make a copy so blend mode only affects this stroke.
        var layer = context
        // Set blend mode.
        layer.blendMode = blend
        // Stroke the path.
        layer.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: stroke.width, lineCap: .round, lineJoin: .round)
        )
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

    /// Convert a screen touch location into letter-page coordinates.
    private func toCanvasPoint(_ location: CGPoint, frame: CGRect) -> CGPoint? {
        // Ignore touches outside the visible letter page.
        guard frame.contains(location) else { return nil }
        // Horizontal position from 0...1 inside page frame.
        let relativeX = (location.x - frame.minX) / frame.width
        // Vertical position from 0...1 inside page frame.
        let relativeY = (location.y - frame.minY) / frame.height
        // Map normalized values into fixed letter coordinate space.
        return CGPoint(
            x: relativeX * CanvasMetrics.letterSize.width,
            y: relativeY * CanvasMetrics.letterSize.height
        )
    }
}
