import Testing
import SwiftUI
@testable import SupaNotes

/// Tests for ToolbarIcon
/// Icons in the toolbar represent either tools (pen, eraser) or colors
@MainActor
struct ToolbarIconTests {

    // MARK: - Static factories

    @Test func colorIcon_producesColorType() {
        let icon = ToolbarIcon.colorIcon(.red, name: "Red")
        #expect(icon.type == .color)
        #expect(icon.name == "Red")
        #expect(icon.colorData != nil)
        #expect(icon.instrumentSettings == nil)
    }

    @Test func toolIcon_pen_hasInstrumentSettings() {
        let icon = ToolbarIcon.toolIcon(.pen)
        #expect(icon.type == .pen)
        #expect(icon.name == "Pen")
        #expect(icon.instrumentSettings != nil)
        #expect(icon.colorData == nil)
    }

    @Test func toolIcon_eraser_hasInstrumentSettings() {
        let icon = ToolbarIcon.toolIcon(.eraser)
        #expect(icon.type == .eraser)
        #expect(icon.instrumentSettings != nil)
    }

    // MARK: - isEssential

    @Test func isEssential_colorPenEraser_areEssential() {
        #expect(ToolbarIcon.colorIcon(.red).isEssential == true)
        #expect(ToolbarIcon.toolIcon(.pen).isEssential == true)
        #expect(ToolbarIcon.toolIcon(.eraser).isEssential == true)
    }

    // MARK: - isEquivalent

    @Test func isEquivalent_sameToolType_returnsTrue() {
        let a = ToolbarIcon.toolIcon(.pen)
        let b = ToolbarIcon.toolIcon(.pen)
        #expect(a.isEquivalent(to: b, colorScheme: .light) == true)
    }

    @Test func isEquivalent_differentToolTypes_returnsFalse() {
        let a = ToolbarIcon.toolIcon(.pen)
        let b = ToolbarIcon.toolIcon(.eraser)
        #expect(a.isEquivalent(to: b, colorScheme: .light) == false)
    }

    @Test func isEquivalent_sameColorIcons_returnsTrue() {
        let a = ToolbarIcon.colorIcon(.red)
        let b = ToolbarIcon.colorIcon(.red)
        #expect(a.isEquivalent(to: b, colorScheme: .light) == true)
    }

    @Test func isEquivalent_differentColorIcons_returnsFalse() {
        let a = ToolbarIcon.colorIcon(.red)
        let b = ToolbarIcon.colorIcon(.blue)
        #expect(a.isEquivalent(to: b, colorScheme: .light) == false)
    }

    @Test func isEquivalent_colorVsTool_returnsFalse() {
        let a = ToolbarIcon.colorIcon(.red)
        let b = ToolbarIcon.toolIcon(.pen)
        #expect(a.isEquivalent(to: b, colorScheme: .light) == false)
    }

    // MARK: - appendToZone

    @Test func appendToZone_colorIcon_appendsToEnd() {
        var icons: [ToolbarIcon] = [
            .toolIcon(.pen),
            .toolIcon(.eraser),
            .colorIcon(.red),
        ]
        let newColor = ToolbarIcon.colorIcon(.blue)
        icons.appendToZone(newColor)
        #expect(icons.last?.id == newColor.id)
    }

    @Test func appendToZone_toolIcon_insertsAfterLastTool() {
        var icons: [ToolbarIcon] = [
            .toolIcon(.pen),
            .colorIcon(.red),
        ]
        // Add a second tool — eraser
        let newTool = ToolbarIcon.toolIcon(.eraser)
        icons.appendToZone(newTool)

        let eraserIndex = icons.firstIndex(where: { $0.id == newTool.id })!
        let colorIndex = icons.firstIndex(where: { $0.type == .color })!
        // Tool should be before the color zone
        #expect(eraserIndex < colorIndex)
    }
}
