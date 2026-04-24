import SwiftUI
import UIKit

// Shared stroke rendering used by both the on-screen canvas and PDF export.
// All methods are pure — they only draw into the provided CGContext.
enum StrokeRenderer {

    // MARK: - Public

    /// Draw all strokes from a document into a CGContext, scaling from letter
    /// space (612×792) to the given rect.
    static func drawStrokes(
        from document: ExcalidrawPageDocument,
        in context: CGContext,
        rect: CGRect
    ) {
        guard !document.strokes.isEmpty else { return }
        context.saveGState()
        context.scaleBy(
            x: rect.width / PageConstants.pageWidth,
            y: rect.height / PageConstants.pageHeight
        )
        for stroke in document.strokes {
            drawStroke(stroke, in: context)
        }
        context.restoreGState()
    }

    /// Draw a single stroke — used by the live canvas for the active preview.
    static func drawStroke(
        _ stroke: ExcalidrawPageStroke,
        in context: CGContext
    ) {
        let points = stroke.points
        guard !points.isEmpty else { return }

        context.saveGState()
        let color = UIColor(stroke.color.toColor())

        // Use variable-width rendering only for fountain pen with pressure data.
        // Ballpoint and legacy strokes use uniform-width rendering (no pressure variation).
        let hasPressure = points.contains { $0.pressure != nil }
        if let penStyle = stroke.penStyle, penStyle == .fountain, hasPressure {
            color.setFill()
            variableWidthStroke(
                points,
                baseWidth: stroke.width,
                penStyle: penStyle,
                tipSharpness: stroke.tipSharpness ?? 0.5,
                pressureSensitivity: stroke.pressureSensitivity ?? 0.5
            )
        } else {
            // Ballpoint and legacy strokes — uniform width, no pressure variation.
            color.setStroke()
            uniformStroke(points.map(\.cgPoint), strokeWidth: stroke.width)
        }

        context.restoreGState()
    }

    // MARK: - Pressure Width Calculation

    /// Compute stroke width at a single point based on pen style, pressure, and sensitivity.
    static func widthForPressure(
        _ pressure: CGFloat,
        baseWidth: CGFloat,
        penStyle: PenStyle,
        tipSharpness: CGFloat,
        pressureSensitivity: CGFloat = 0.5
    ) -> CGFloat {
        // Blend raw pressure toward 0.5 (neutral) based on sensitivity.
        // At sensitivity=0, pressure is always 0.5 (uniform width).
        // At sensitivity=1, raw pressure is used directly.
        let raw = min(max(pressure, 0), 1)
        let p = 0.5 + (raw - 0.5) * min(max(pressureSensitivity, 0), 1)
        let multiplier: CGFloat
        switch penStyle {
        case .ballpoint:
            // Ballpoint uses uniform width — no pressure variation.
            multiplier = 1.0
        case .fountain:
            // Sharp contrast between light and heavy strokes.
            let minScale = max(0.05, 0.5 - tipSharpness * 0.45)
            multiplier = minScale + (1.0 - minScale) * pow(p, 1.5)
        }
        return baseWidth * multiplier
    }

    // MARK: - Variable Width Rendering

    /// Draw a pressure-sensitive stroke as a filled polygon ribbon.
    private static func variableWidthStroke(
        _ points: [ExcalidrawPagePoint],
        baseWidth: CGFloat,
        penStyle: PenStyle,
        tipSharpness: CGFloat,
        pressureSensitivity: CGFloat
    ) {
        guard !points.isEmpty else { return }

        let cgPoints = points.map(\.cgPoint)

        // Single dot.
        if cgPoints.count == 1 {
            let w = widthForPressure(points[0].pressure ?? 0.5, baseWidth: baseWidth, penStyle: penStyle, tipSharpness: tipSharpness, pressureSensitivity: pressureSensitivity)
            let dotRect = CGRect(x: cgPoints[0].x - w * 0.5, y: cgPoints[0].y - w * 0.5, width: w, height: w)
            UIBezierPath(ovalIn: dotRect).fill()
            return
        }

        // Build left and right edge points for the ribbon outline.
        var leftEdge: [CGPoint] = []
        var rightEdge: [CGPoint] = []

        for i in 0 ..< cgPoints.count {
            let pressure = points[i].pressure ?? 0.5
            let halfWidth = widthForPressure(pressure, baseWidth: baseWidth, penStyle: penStyle, tipSharpness: tipSharpness, pressureSensitivity: pressureSensitivity) * 0.5

            // Compute tangent direction at this point.
            let tangent: CGPoint
            if i == 0 {
                tangent = unitVector(from: cgPoints[0], to: cgPoints[1])
            } else if i == cgPoints.count - 1 {
                tangent = unitVector(from: cgPoints[i - 1], to: cgPoints[i])
            } else {
                // Average tangent from neighbors for smoother normals.
                let t1 = unitVector(from: cgPoints[i - 1], to: cgPoints[i])
                let t2 = unitVector(from: cgPoints[i], to: cgPoints[i + 1])
                let avg = CGPoint(x: t1.x + t2.x, y: t1.y + t2.y)
                let len = hypot(avg.x, avg.y)
                tangent = len > 0.001 ? CGPoint(x: avg.x / len, y: avg.y / len) : t1
            }

            // Normal is perpendicular to tangent.
            let normal = CGPoint(x: -tangent.y, y: tangent.x)
            leftEdge.append(CGPoint(x: cgPoints[i].x + normal.x * halfWidth, y: cgPoints[i].y + normal.y * halfWidth))
            rightEdge.append(CGPoint(x: cgPoints[i].x - normal.x * halfWidth, y: cgPoints[i].y - normal.y * halfWidth))
        }

        // Build filled polygon: left edge forward, right edge backward.
        let path = UIBezierPath()
        path.move(to: leftEdge[0])
        for i in 1 ..< leftEdge.count {
            path.addLine(to: leftEdge[i])
        }
        for i in stride(from: rightEdge.count - 1, through: 0, by: -1) {
            path.addLine(to: rightEdge[i])
        }
        path.close()
        path.fill()

        // Draw round caps at start and end for clean endpoints.
        let startW = widthForPressure(points[0].pressure ?? 0.5, baseWidth: baseWidth, penStyle: penStyle, tipSharpness: tipSharpness, pressureSensitivity: pressureSensitivity)
        let endW = widthForPressure(points[points.count - 1].pressure ?? 0.5, baseWidth: baseWidth, penStyle: penStyle, tipSharpness: tipSharpness, pressureSensitivity: pressureSensitivity)
        UIBezierPath(ovalIn: CGRect(x: cgPoints[0].x - startW * 0.5, y: cgPoints[0].y - startW * 0.5, width: startW, height: startW)).fill()
        UIBezierPath(ovalIn: CGRect(x: cgPoints.last!.x - endW * 0.5, y: cgPoints.last!.y - endW * 0.5, width: endW, height: endW)).fill()
    }

    /// Unit vector from one point to another.
    private static func unitVector(from a: CGPoint, to b: CGPoint) -> CGPoint {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len = hypot(dx, dy)
        guard len > 0.001 else { return CGPoint(x: 1, y: 0) }
        return CGPoint(x: dx / len, y: dy / len)
    }

    // MARK: - Legacy Uniform Rendering

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
