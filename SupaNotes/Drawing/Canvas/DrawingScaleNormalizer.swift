import CoreGraphics
import PencilKit

enum DrawingScaleNormalizer {
    // Backward-compatibility fallback for drawings saved before `drawingScale` existed.
    static let legacyUnversionedScale: CGFloat = 4.0

    static func authoredScale(for page: Page) -> CGFloat {
        guard let stored = page.drawingScale, stored > 0 else { return legacyUnversionedScale }
        return CGFloat(stored)
    }

    static func normalizedDrawing(for page: Page) -> PKDrawing? {
        guard !page.drawingData.isEmpty, let drawing = try? PKDrawing(data: page.drawingData) else { return nil }
        return normalize(drawing: drawing, from: authoredScale(for: page), to: PageConstants.renderScale)
    }

    static func normalize(drawing: PKDrawing, from sourceScale: CGFloat, to targetScale: CGFloat) -> PKDrawing {
        guard sourceScale > 0, targetScale > 0 else { return drawing }
        let factor = targetScale / sourceScale
        guard abs(factor - 1.0) > 0.0001 else { return drawing }
        return drawing.transformed(using: CGAffineTransform(scaleX: factor, y: factor))
    }
}
