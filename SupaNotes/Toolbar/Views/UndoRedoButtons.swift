import SwiftUI

/// Shows two buttons — Undo and Redo — in the toolbar.
/// Undo reverses the last action (e.g. removes a stroke you just drew).
/// Redo re-applies an action you undid (e.g. puts that stroke back).
/// The buttons automatically go dim when there is nothing to undo or redo.
struct UndoRedoButtons: View {
    /// The system object that tracks the history of actions the user can undo/redo.
    /// It is optional because some screens may not support undo.
    var undoManager: UndoManager?

    /// When the user is dragging the toolbar to reposition it, tapping undo/redo
    /// would be an accident, so we block the action while this is true.
    var didRepositionToolbar: Bool

    /// Whether the undo button should be active right now.
    /// This updates automatically whenever the undo history changes.
    @State private var canUndo = false
    /// Whether the redo button should be active right now.
    @State private var canRedo = false

    var body: some View {
        // The undo button (arrow curving back to the left).
        actionButton(icon: "arrow.uturn.backward", enabled: canUndo) { undoManager?.undo() }

        // The redo button (arrow curving forward to the right).
        // We attach all our listeners here so they are set up once when this view appears.
        actionButton(icon: "arrow.uturn.forward", enabled: canRedo) { undoManager?.redo() }
            // Sync button states as soon as the view appears on screen.
            .onAppear { updateUndoState() }
            // Re-sync whenever the system tells us an undo just happened.
            .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidUndoChange)) { _ in updateUndoState() }
            // Re-sync whenever the system tells us a redo just happened.
            .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidRedoChange)) { _ in updateUndoState() }
            // Re-sync whenever a group of actions finishes being recorded (e.g. end of a stroke).
            .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidCloseUndoGroup)) { _ in updateUndoState() }
    }

    /// Builds a single undo or redo button.
    /// - Parameters:
    ///   - icon: The SF Symbol name for the arrow image to show.
    ///   - enabled: Whether this button should be tappable right now.
    ///   - action: What to do when the button is tapped (undo or redo).
    private func actionButton(icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            // Ignore taps while the toolbar is being dragged to a new position.
            guard !didRepositionToolbar else { return }
            // Perform the undo or redo action.
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: Design.FontSize.toolIcon))
                // Give the button a large enough tap area so it is easy to hit.
                .frame(width: ToolbarConstants.tapTargetSize, height: ToolbarConstants.tapTargetSize)
                // Make the whole frame tappable, not just the icon pixels.
                .contentShape(Rectangle())
        }
        // Disable the button when there is nothing to undo/redo.
        .disabled(!enabled)
        // Dim the button when disabled so the user knows it is unavailable.
        .opacity(enabled ? 1 : 0.3)
    }

    /// Asks the undo manager whether undo and redo are currently possible,
    /// then updates the two state variables so the buttons re-render correctly.
    private func updateUndoState() {
        // canUndo is false if undoManager is nil or has no recorded actions.
        canUndo = undoManager?.canUndo ?? false
        // canRedo is false if undoManager is nil or has no undone actions to redo.
        canRedo = undoManager?.canRedo ?? false
    }
}
