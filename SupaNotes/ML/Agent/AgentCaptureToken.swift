import UIKit

/// Shared token that PagedCanvasContainer registers a capture closure on.
/// NoteEditorView holds this and passes it down so it can trigger capture at any time.
final class AgentCaptureToken {
    /// Capture the visible portion of the current page as a UIImage (cropped to page bounds only).
    var captureViewport: (() -> UIImage?)?
}
