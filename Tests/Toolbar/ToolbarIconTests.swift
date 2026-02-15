import Testing
import SwiftUI
@testable import SupaNotes

struct ToolbarIconTests {

    // MARK: - Static factories

    @Test func colorIcon_producesColorType() {
        let icon = ToolbarIcon.colorIcon(.red, name: "Red", colorScheme: .light)
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

    @Test func toolIcon_highlighter_hasInstrumentSettings() {
        let icon = ToolbarIcon.toolIcon(.highlighter)
        #expect(icon.type == .highlighter)
        #expect(icon.instrumentSettings != nil)
    }

    @Test func toolIcon_lasso_hasNoInstrumentSettings() {
        let icon = ToolbarIcon.toolIcon(.lasso)
        #expect(icon.type == .lasso)
        #expect(icon.instrumentSettings == nil)
    }

    // MARK: - isEssential

    @Test func isEssential_colorPenEraser_areEssential() {
        #expect(ToolbarIcon.colorIcon(.red, colorScheme: .light).isEssential == true)
        #expect(ToolbarIcon.toolIcon(.pen).isEssential == true)
        #expect(ToolbarIcon.toolIcon(.eraser).isEssential == true)
    }

    @Test func isEssential_highlighterLasso_areNotEssential() {
        #expect(ToolbarIcon.toolIcon(.highlighter).isEssential == false)
        #expect(ToolbarIcon.toolIcon(.lasso).isEssential == false)
    }

    // MARK: - isEquivalent (zone-based)

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
        let a = ToolbarIcon.colorIcon(.red, colorScheme: .light)
        let b = ToolbarIcon.colorIcon(.red, colorScheme: .light)
        #expect(a.isEquivalent(to: b, colorScheme: .light) == true)
    }

    @Test func isEquivalent_differentColorIcons_returnsFalse() {
        let a = ToolbarIcon.colorIcon(.red, colorScheme: .light)
        let b = ToolbarIcon.colorIcon(.blue, colorScheme: .light)
        #expect(a.isEquivalent(to: b, colorScheme: .light) == false)
    }

    @Test func isEquivalent_colorVsTool_returnsFalse() {
        let a = ToolbarIcon.colorIcon(.red, colorScheme: .light)
        let b = ToolbarIcon.toolIcon(.pen)
        #expect(a.isEquivalent(to: b, colorScheme: .light) == false)
    }

    // MARK: - appendToZone

    @Test func appendToZone_colorIcon_appendsToEnd() {
        var icons: [ToolbarIcon] = [
            .toolIcon(.pen),
            .toolIcon(.eraser),
            .colorIcon(.red, colorScheme: .light),
        ]
        let newColor = ToolbarIcon.colorIcon(.blue, colorScheme: .light)
        icons.appendToZone(newColor)
        #expect(icons.last?.id == newColor.id)
    }

    @Test func appendToZone_toolIcon_insertsAfterLastTool() {
        var icons: [ToolbarIcon] = [
            .toolIcon(.pen),
            .toolIcon(.eraser),
            .colorIcon(.red, colorScheme: .light),
        ]
        let newTool = ToolbarIcon.toolIcon(.highlighter)
        icons.appendToZone(newTool)

        let highlighterIndex = icons.firstIndex(where: { $0.id == newTool.id })!
        let colorIndex = icons.firstIndex(where: { $0.type == .color })!
        #expect(highlighterIndex < colorIndex)
    }
}
