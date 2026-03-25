import PencilKit
import UIKit

/// Extracts stroke bounding box data from a PKDrawing for the agent.
/// Coordinates are in image space (612×792).
struct AgentStrokeSerializer {

    /// Serialize strokes as a JSON-friendly array of bounding boxes.
    /// Each stroke has pre-computed corners: {"id":N,"x1":left,"y1":top,"x2":right,"y2":bottom}.
    /// Coordinates are in image space (divided by renderScale).
    static func serialize(drawing: PKDrawing) -> [[String: Any]] {
        let scale = 1.0 / PageConstants.renderScale
        return drawing.strokes.enumerated().map { (i, stroke) in
            let b = stroke.renderBounds
            return [
                "id": i,
                "x1": round(b.minX * scale),
                "y1": round(b.minY * scale),
                "x2": round(b.maxX * scale),
                "y2": round(b.maxY * scale)
            ]
        }
    }

    /// Serialize strokes to a JSON string.
    static func jsonString(drawing: PKDrawing) -> String? {
        let data = serialize(drawing: drawing)
        guard !data.isEmpty,
              let json = try? JSONSerialization.data(withJSONObject: data, options: []),
              let str = String(data: json, encoding: .utf8) else { return nil }
        return str
    }
}
