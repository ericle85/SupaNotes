import PencilKit
import CoreGraphics

enum LassoHitTest {
    static func pointInPolygon(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let pi = polygon[i]
            let pj = polygon[j]
            if (pi.y > point.y) != (pj.y > point.y) {
                let xIntersect = (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x
                if point.x < xIntersect { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    static func selectedIndices(in drawing: PKDrawing, polygon: [CGPoint]) -> [Int] {
        drawing.strokes.enumerated().compactMap { idx, stroke in
            let pts = sampledPoints(of: stroke)
            guard !pts.isEmpty else { return nil }
            let inside = pts.filter { pointInPolygon($0, polygon: polygon) }.count
            return Double(inside) / Double(pts.count) >= 0.5 ? idx : nil
        }
    }

    private static func sampledPoints(of stroke: PKStroke) -> [CGPoint] {
        let path = stroke.path
        let transform = stroke.transform
        guard path.count > 0 else { return [] }
        let step = max(1, path.count / 32)
        var points: [CGPoint] = []
        var i = 0
        while i < path.count {
            points.append(path[i].location.applying(transform))
            i += step
        }
        return points
    }

    static func unionBounds(ofStrokes strokes: [PKStroke]) -> CGRect? {
        guard !strokes.isEmpty else { return nil }
        return PKDrawing(strokes: strokes).bounds
    }
}
