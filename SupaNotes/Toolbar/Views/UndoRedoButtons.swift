import SwiftUI

struct UndoRedoButtons: View {
    var undoManager: UndoManager?
    var didRepositionToolbar: Bool

    @State private var canUndo = false
    @State private var canRedo = false

    var body: some View {
        Button {
            guard !didRepositionToolbar else { return }
            undoManager?.undo()
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: Design.FontSize.toolIcon))
                .frame(width: ToolbarConstants.tapTargetSize, height: ToolbarConstants.tapTargetSize)
                .contentShape(Rectangle())
        }
        .disabled(!canUndo)
        .opacity(canUndo ? 1 : 0.3)

        Button {
            guard !didRepositionToolbar else { return }
            undoManager?.redo()
        } label: {
            Image(systemName: "arrow.uturn.forward")
                .font(.system(size: Design.FontSize.toolIcon))
                .frame(width: ToolbarConstants.tapTargetSize, height: ToolbarConstants.tapTargetSize)
                .contentShape(Rectangle())
        }
        .disabled(!canRedo)
        .opacity(canRedo ? 1 : 0.3)
        .onAppear { updateUndoState() }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidUndoChange)) { _ in updateUndoState() }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidRedoChange)) { _ in updateUndoState() }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidCloseUndoGroup)) { _ in updateUndoState() }
    }

    private func updateUndoState() {
        canUndo = undoManager?.canUndo ?? false
        canRedo = undoManager?.canRedo ?? false
    }
}
