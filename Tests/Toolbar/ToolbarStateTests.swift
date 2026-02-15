import Testing
import SwiftUI
@testable import SupaNotes

/// Tests for ToolbarState
/// This tracks which tool is currently active and provides information about tool settings
@MainActor
struct ToolbarStateTests {

    // MARK: - switchToPreviousTool
    // Tests for swapping between the current tool and the previously used tool
    // (Think of this like keyboard shortcuts that let you quickly toggle between two tools)

    @Test func switchToPreviousTool_swapsActiveAndPrevious() {
        // Start with pen as active and eraser as previous
        let state = ToolbarState()
        state.activeTool = .pen
        state.previousTool = .eraser

        // Switch to the previous tool
        state.switchToPreviousTool()

        // Now eraser should be active and pen should be the previous tool
        #expect(state.activeTool == .eraser)
        #expect(state.previousTool == .pen)
    }

    @Test func switchToPreviousTool_doubleSwap_restoresOriginal() {
        // Start with highlighter as active and lasso as previous
        let state = ToolbarState()
        state.activeTool = .highlighter
        state.previousTool = .lasso

        // Switch twice - should toggle back to the original
        state.switchToPreviousTool()
        state.switchToPreviousTool()

        // Should be back where we started
        #expect(state.activeTool == .highlighter)
        #expect(state.previousTool == .lasso)
    }

    // MARK: - instrumentWidth
    // Tests for getting the current width setting of a tool

    @Test func instrumentWidth_forPen_returnsSettingsWidth() {
        // Create state with a pen tool
        let state = ToolbarState()
        let penIcon = ToolbarIcon.toolIcon(.pen)
        state.toolbarIcons = [penIcon]

        // Get the pen's width setting
        let width = state.instrumentWidth(for: .pen)

        // Should match the pen's default width setting
        #expect(width == WritingInstrumentSettings.pen().width)
    }

    @Test func instrumentWidth_forMissingType_returnsPenDefault() {
        // Create state with no tools
        let state = ToolbarState()
        state.toolbarIcons = []

        // Ask for the highlighter's width even though it doesn't exist
        let width = state.instrumentWidth(for: .highlighter)

        // Should fall back to pen's default width (a safe default)
        #expect(width == WritingInstrumentSettings.pen().width)
    }

    @Test func instrumentWidth_forEraser_returnsEraserWidth() {
        // Create state with an eraser tool
        let state = ToolbarState()
        let eraserIcon = ToolbarIcon.toolIcon(.eraser)
        state.toolbarIcons = [eraserIcon]

        // Get the eraser's width setting
        let width = state.instrumentWidth(for: .eraser)

        // Should match the eraser's width setting (which is larger than a pen)
        #expect(width == WritingInstrumentSettings.eraser().width)
    }
}
