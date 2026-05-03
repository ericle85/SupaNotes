import CoreGraphics
import SwiftUI

// MARK: - Drawing Data Types

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

// MARK: - Codec

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
