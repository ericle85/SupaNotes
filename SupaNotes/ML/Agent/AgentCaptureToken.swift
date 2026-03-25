import UIKit

/// Shared token that PagedCanvasContainer registers a capture closure on.
/// NoteEditorView holds this and passes it down so it can trigger capture at any time.
final class AgentCaptureToken {
    var captureCurrentPage: (() -> UIImage?)?
}
