import UIKit
import PencilKit

/// Shared token that PagedCanvasContainer registers a capture closure on.
/// NoteEditorView holds this and passes it down so it can trigger capture at any time.
final class AgentCaptureToken {
    /// Capture the current page. Pass a screen-space CGRect to annotate the selected region on the image.
    var captureCurrentPage: ((CGRect?) -> UIImage?)?
    /// Convert a rect in page image space (0–612 × 0–792) to screen/SwiftUI coordinate space.
    var imageRectToScreenRect: ((CGRect) -> CGRect)?
    /// Simulate a tap at a point in page image space (0–612 × 0–792).
    var tapAtImagePoint: ((CGPoint) -> Void)?
    /// Convert a screen-space rect to image space (0–612 × 0–792).
    var screenRectToImageRect: ((CGRect) -> CGRect)?
    /// Get the PKDrawing for the current page.
    var currentPageDrawing: (() -> PKDrawing?)?
}
