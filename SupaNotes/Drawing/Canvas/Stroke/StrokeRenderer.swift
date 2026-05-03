import SwiftUI
import UIKit

// Shared stroke rendering used by both the on-screen canvas and PDF export.
// All methods are pure — they only draw into the provided CGContext.
enum StrokeRenderer {

    // MARK: - Public

    /// Draw all strokes from a page into a CGContext, scaling from the
    /// page's coordinate space to the given rect.
    static func drawStrokes(
        from currentPage: DrawingPage,
        in context: CGContext,
        rect: CGRect,
        pageSize: CGSize = CGSize(width: PageConstants.pageWidth, height: PageConstants.pageHeight)
    ) {
        guard !currentPage.strokes.isEmpty else { return }
        context.saveGState()
        context.scaleBy(
            x: rect.width / pageSize.width,
            y: rect.height / pageSize.height
        )
        for stroke in currentPage.strokes {
            drawStroke(stroke, in: context)
        }
        context.restoreGState()
    }

    /// Draw a single stroke with uniform width.
    static func drawStroke(
        _ stroke: Stroke,
        in context: CGContext
    ) {
        let points = stroke.points
        guard !points.isEmpty else { return }

        context.saveGState()
        let color = UIColor(stroke.color.toColor())
        color.setStroke()
        uniformStroke(points.map(\.cgPoint), strokeWidth: stroke.width)
        context.restoreGState()
    }

    // MARK: - Private

    /// Draw one continuous segment using uniform-width cubic Bézier curves.
    private static func uniformStroke(_ points: [CGPoint], strokeWidth: CGFloat) {
        guard !points.isEmpty else { return }
        let path = UIBezierPath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.lineWidth = strokeWidth

        if points.count == 1 {
            let dotRect = CGRect(
                x: points[0].x - strokeWidth * 0.5,
                y: points[0].y - strokeWidth * 0.5,
                width: strokeWidth,
                height: strokeWidth
            )
            path.append(UIBezierPath(ovalIn: dotRect))
        } else if points.count == 2 {
            path.move(to: points[0])
            path.addLine(to: points[1])
        } else {
            // Catmull-Rom → cubic Bézier for smooth curves through each point.
            path.move(to: points[0])
            for index in 0 ..< (points.count - 1) {
                let previousNeighbor = index > 0 ? points[index - 1] : points[index]
                let segmentStart = points[index]
                let segmentEnd = points[index + 1]
                let nextNeighbor = (index + 2) < points.count ? points[index + 2] : points[index + 1]

                let controlPoint1 = CGPoint(
                    x: segmentStart.x + (segmentEnd.x - previousNeighbor.x) / 6,
                    y: segmentStart.y + (segmentEnd.y - previousNeighbor.y) / 6
                )
                let controlPoint2 = CGPoint(
                    x: segmentEnd.x - (nextNeighbor.x - segmentStart.x) / 6,
                    y: segmentEnd.y - (nextNeighbor.y - segmentStart.y) / 6
                )

                path.addCurve(to: segmentEnd, controlPoint1: controlPoint1, controlPoint2: controlPoint2)
            }
        }
        path.stroke()
    }
}
