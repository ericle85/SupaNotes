import CoreGraphics
import PencilKit

enum DrawingCoordinateSpace {
    // Backward-compatibility fallback for drawings saved before `drawingScale` existed.
    static let legacyUnversionedScale: CGFloat = 4.0
    static let storageScale: CGFloat = 1.0

    static func storageScale(for page: Page) -> CGFloat {
        guard let stored = page.drawingScale, stored > 0 else { return legacyUnversionedScale }
        return CGFloat(stored)
    }

    static func logicalDrawing(for page: Page) -> PKDrawing? {
        guard !page.drawingData.isEmpty, let drawing = try? PKDrawing(data: page.drawingData) else { return nil }
        return scale(drawing: drawing, from: storageScale(for: page), to: storageScale)
    }

    static func presentationDrawing(for page: Page, presentationScale: CGFloat) -> PKDrawing? {
        guard let drawing = logicalDrawing(for: page) else { return nil }
        return scale(drawing: drawing, from: storageScale, to: presentationScale)
    }

    static func storageDrawing(fromPresentation drawing: PKDrawing, presentationScale: CGFloat) -> PKDrawing {
        scale(drawing: drawing, from: presentationScale, to: storageScale)
    }

    static func scale(drawing: PKDrawing, from sourceScale: CGFloat, to targetScale: CGFloat) -> PKDrawing {
        guard sourceScale > 0, targetScale > 0 else { return drawing }
        let factor = targetScale / sourceScale
        guard abs(factor - 1.0) > 0.0001 else { return drawing }
        return drawing.transformed(using: CGAffineTransform(scaleX: factor, y: factor))
    }
}
