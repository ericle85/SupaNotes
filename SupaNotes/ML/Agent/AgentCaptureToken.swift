import UIKit

/// Shared token that PagedCanvasContainer registers a capture closure on.
/// NoteEditorView holds this and passes it down so it can trigger capture at any time.
final class AgentCaptureToken {
    /// Capture the current page. Pass a screen-space CGRect to annotate the selected region on the image.
    var captureCurrentPage: ((CGRect?) -> UIImage?)?
}
