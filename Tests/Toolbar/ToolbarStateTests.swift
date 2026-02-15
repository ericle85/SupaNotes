import Testing
import SwiftUI
@testable import SupaNotes

@MainActor
struct ToolbarStateTests {

    // MARK: - switchToPreviousTool

    @Test func switchToPreviousTool_swapsActiveAndPrevious() {
        let state = ToolbarState()
        state.activeTool = .pen
        state.previousTool = .eraser

        state.switchToPreviousTool()

        #expect(state.activeTool == .eraser)
        #expect(state.previousTool == .pen)
    }

    @Test func switchToPreviousTool_doubleSwap_restoresOriginal() {
        let state = ToolbarState()
        state.activeTool = .highlighter
        state.previousTool = .lasso

        state.switchToPreviousTool()
        state.switchToPreviousTool()

        #expect(state.activeTool == .highlighter)
        #expect(state.previousTool == .lasso)
    }

    // MARK: - instrumentWidth

    @Test func instrumentWidth_forPen_returnsSettingsWidth() {
        let state = ToolbarState()
        let penIcon = ToolbarIcon.toolIcon(.pen)
        state.toolbarIcons = [penIcon]

        let width = state.instrumentWidth(for: .pen)

        #expect(width == WritingInstrumentSettings.pen().width)
    }

    @Test func instrumentWidth_forMissingType_returnsPenDefault() {
        let state = ToolbarState()
        state.toolbarIcons = []

        let width = state.instrumentWidth(for: .highlighter)

        // Falls back to pen default
        #expect(width == WritingInstrumentSettings.pen().width)
    }

    @Test func instrumentWidth_forEraser_returnsEraserWidth() {
        let state = ToolbarState()
        let eraserIcon = ToolbarIcon.toolIcon(.eraser)
        state.toolbarIcons = [eraserIcon]

        let width = state.instrumentWidth(for: .eraser)

        #expect(width == WritingInstrumentSettings.eraser().width)
    }
}
