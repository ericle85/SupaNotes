import Testing
import SwiftUI
@testable import SupaNotes

/// Tests for ToolbarIcon
/// Icons in the toolbar represent either tools (pen, eraser, etc.) or colors
/// This tests how to create them and check their properties
struct ToolbarIconTests {

    // MARK: - Static factories
    // Factory methods are helper functions that create icons - tests they work correctly

    @Test func colorIcon_producesColorType() {
        // Create a color icon using the factory function
        let icon = ToolbarIcon.colorIcon(.red, name: "Red", colorScheme: .light)
        // Verify it's set up as a color icon, not a tool
        #expect(icon.type == .color)           // Type should be color
        #expect(icon.name == "Red")            // Name should be "Red"
        #expect(icon.colorData != nil)         // Should have color data
        #expect(icon.instrumentSettings == nil) // Should NOT have tool settings
    }

    @Test func toolIcon_pen_hasInstrumentSettings() {
        // Create a pen icon
        let icon = ToolbarIcon.toolIcon(.pen)
        // Verify it's set up as a tool, not a color
        #expect(icon.type == .pen)                      // Type should be pen
        #expect(icon.name == "Pen")                     // Name should be "Pen"
        #expect(icon.instrumentSettings != nil)         // Should have tool settings
        #expect(icon.colorData == nil)                  // Should NOT have color data
    }

    @Test func toolIcon_eraser_hasInstrumentSettings() {
        // Create an eraser icon
        let icon = ToolbarIcon.toolIcon(.eraser)
        // Verify eraser has tool settings (like width and pressure)
        #expect(icon.type == .eraser)
        #expect(icon.instrumentSettings != nil)  // Should have settings for eraser width
    }

    @Test func toolIcon_highlighter_hasInstrumentSettings() {
        // Create a highlighter icon
        let icon = ToolbarIcon.toolIcon(.highlighter)
        // Verify highlighter has tool settings
        #expect(icon.type == .highlighter)
        #expect(icon.instrumentSettings != nil)  // Should have settings for highlight width
    }

    @Test func toolIcon_lasso_hasNoInstrumentSettings() {
        // Create a lasso icon (used for selecting/erasing regions)
        let icon = ToolbarIcon.toolIcon(.lasso)
        // Lasso doesn't have width settings - it's just for selecting
        #expect(icon.type == .lasso)
        #expect(icon.instrumentSettings == nil)  // Lasso doesn't need width settings
    }

    // MARK: - isEssential
    // Tests checking if a tool is essential (can't be removed) vs optional (can be removed)

    @Test func isEssential_colorPenEraser_areEssential() {
        // These three are fundamental to a notes app - they can't be removed
        #expect(ToolbarIcon.colorIcon(.red, colorScheme: .light).isEssential == true)
        #expect(ToolbarIcon.toolIcon(.pen).isEssential == true)
        #expect(ToolbarIcon.toolIcon(.eraser).isEssential == true)
    }

    @Test func isEssential_highlighterLasso_areNotEssential() {
        // These are nice-to-have features but could be removed if needed
        #expect(ToolbarIcon.toolIcon(.highlighter).isEssential == false)
        #expect(ToolbarIcon.toolIcon(.lasso).isEssential == false)
    }

    // MARK: - isEquivalent (zone-based)
    // Tests checking if two icons are "the same" for purposes of the toolbar layout

    @Test func isEquivalent_sameToolType_returnsTrue() {
        // Two pen icons are equivalent
        let a = ToolbarIcon.toolIcon(.pen)
        let b = ToolbarIcon.toolIcon(.pen)
        #expect(a.isEquivalent(to: b, colorScheme: .light) == true)
    }

    @Test func isEquivalent_differentToolTypes_returnsFalse() {
        // A pen and eraser are not equivalent
        let a = ToolbarIcon.toolIcon(.pen)
        let b = ToolbarIcon.toolIcon(.eraser)
        #expect(a.isEquivalent(to: b, colorScheme: .light) == false)
    }

    @Test func isEquivalent_sameColorIcons_returnsTrue() {
        // Two red color icons are equivalent
        let a = ToolbarIcon.colorIcon(.red, colorScheme: .light)
        let b = ToolbarIcon.colorIcon(.red, colorScheme: .light)
        #expect(a.isEquivalent(to: b, colorScheme: .light) == true)
    }

    @Test func isEquivalent_differentColorIcons_returnsFalse() {
        // Red and blue are different colors
        let a = ToolbarIcon.colorIcon(.red, colorScheme: .light)
        let b = ToolbarIcon.colorIcon(.blue, colorScheme: .light)
        #expect(a.isEquivalent(to: b, colorScheme: .light) == false)
    }

    @Test func isEquivalent_colorVsTool_returnsFalse() {
        // A color icon and a tool icon are never equivalent
        let a = ToolbarIcon.colorIcon(.red, colorScheme: .light)
        let b = ToolbarIcon.toolIcon(.pen)
        #expect(a.isEquivalent(to: b, colorScheme: .light) == false)
    }

    // MARK: - appendToZone
    // Tests for adding a new icon to the toolbar, maintaining zone separation
    // (tools stay together, colors stay together)

    @Test func appendToZone_colorIcon_appendsToEnd() {
        // Start with some tools and a color
        var icons: [ToolbarIcon] = [
            .toolIcon(.pen),
            .toolIcon(.eraser),
            .colorIcon(.red, colorScheme: .light),
        ]
        // Add a new blue color
        let newColor = ToolbarIcon.colorIcon(.blue, colorScheme: .light)
        icons.appendToZone(newColor)
        // The new color should be at the end (in the color zone)
        #expect(icons.last?.id == newColor.id)
    }

    @Test func appendToZone_toolIcon_insertsAfterLastTool() {
        // Start with some tools and a color
        var icons: [ToolbarIcon] = [
            .toolIcon(.pen),
            .toolIcon(.eraser),
            .colorIcon(.red, colorScheme: .light),
        ]
        // Add a new tool (highlighter)
        let newTool = ToolbarIcon.toolIcon(.highlighter)
        icons.appendToZone(newTool)

        // Find where the new tool ended up
        let highlighterIndex = icons.firstIndex(where: { $0.id == newTool.id })!
        let colorIndex = icons.firstIndex(where: { $0.type == .color })!
        // The new tool should be BEFORE the colors (in the tool zone)
        #expect(highlighterIndex < colorIndex)
    }
}
