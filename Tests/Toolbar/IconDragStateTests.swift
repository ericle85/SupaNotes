import Testing
import SwiftUI
@testable import SupaNotes

@MainActor
struct IconDragStateTests {

    // MARK: - reset()

    @Test func reset_clearsAllProperties() {
        let state = IconDragState()
        state.draggedIconID = UUID()
        state.dragTranslation = CGSize(width: 100, height: 50)
        state.isDraggingOutOfBounds = true
        state.dragStartZoneIndex = 2
        state.proposedZoneIndex = 4
        state.dragZoneIsColor = true

        state.reset(animated: false)

        #expect(state.draggedIconID == nil)
        #expect(state.dragTranslation == .zero)
        #expect(state.isDraggingOutOfBounds == false)
        #expect(state.dragStartZoneIndex == nil)
        #expect(state.proposedZoneIndex == nil)
        #expect(state.dragZoneIsColor == false)
    }

    // MARK: - reorderDisplacement()

    private func makeToolIcons() -> [ToolbarIcon] {
        [
            ToolbarIcon.toolIcon(.pen),
            ToolbarIcon.toolIcon(.eraser),
            ToolbarIcon.toolIcon(.highlighter),
        ]
    }

    private func makeColorIcons() -> [ToolbarIcon] {
        [
            ToolbarIcon.colorIcon(.red, colorScheme: .light),
            ToolbarIcon.colorIcon(.blue, colorScheme: .light),
            ToolbarIcon.colorIcon(.green, colorScheme: .light),
        ]
    }

    @Test func reorderDisplacement_noDrag_returnsZero() {
        let state = IconDragState()
        let tools = makeToolIcons()
        let colors = makeColorIcons()
        let displacement = state.reorderDisplacement(for: tools[0], toolIcons: tools, colorIcons: colors, slotPitch: 50)
        #expect(displacement == 0)
    }

    @Test func reorderDisplacement_forwardDrag_shiftsBackward() {
        let tools = makeToolIcons()
        let colors = makeColorIcons()
        let state = IconDragState()
        state.draggedIconID = tools[0].id
        state.dragStartZoneIndex = 0
        state.proposedZoneIndex = 2
        state.dragZoneIsColor = false

        // Icon at index 1 is between start (0) and proposed (2), should shift backward
        let displacement = state.reorderDisplacement(for: tools[1], toolIcons: tools, colorIcons: colors, slotPitch: 50)
        #expect(displacement == -50)
    }

    @Test func reorderDisplacement_forwardDrag_endIcon_shiftsBackward() {
        let tools = makeToolIcons()
        let colors = makeColorIcons()
        let state = IconDragState()
        state.draggedIconID = tools[0].id
        state.dragStartZoneIndex = 0
        state.proposedZoneIndex = 2
        state.dragZoneIsColor = false

        // Icon at index 2 == proposed, should also shift backward
        let displacement = state.reorderDisplacement(for: tools[2], toolIcons: tools, colorIcons: colors, slotPitch: 50)
        #expect(displacement == -50)
    }

    @Test func reorderDisplacement_backwardDrag_shiftsForward() {
        let tools = makeToolIcons()
        let colors = makeColorIcons()
        let state = IconDragState()
        state.draggedIconID = tools[2].id
        state.dragStartZoneIndex = 2
        state.proposedZoneIndex = 0
        state.dragZoneIsColor = false

        // Icon at index 1 is between proposed (0) and start (2), should shift forward
        let displacement = state.reorderDisplacement(for: tools[1], toolIcons: tools, colorIcons: colors, slotPitch: 50)
        #expect(displacement == 50)
    }

    @Test func reorderDisplacement_outsideRange_returnsZero() {
        let tools = makeToolIcons()
        let colors = makeColorIcons()
        let state = IconDragState()
        state.draggedIconID = tools[0].id
        state.dragStartZoneIndex = 0
        state.proposedZoneIndex = 1
        state.dragZoneIsColor = false

        // Icon at index 2 is outside the drag range [0, 1]
        let displacement = state.reorderDisplacement(for: tools[2], toolIcons: tools, colorIcons: colors, slotPitch: 50)
        #expect(displacement == 0)
    }

    @Test func reorderDisplacement_wrongZone_returnsZero() {
        let tools = makeToolIcons()
        let colors = makeColorIcons()
        let state = IconDragState()
        state.draggedIconID = tools[0].id
        state.dragStartZoneIndex = 0
        state.proposedZoneIndex = 2
        state.dragZoneIsColor = false

        // Color icon should not be displaced by a tool zone drag
        let displacement = state.reorderDisplacement(for: colors[1], toolIcons: tools, colorIcons: colors, slotPitch: 50)
        #expect(displacement == 0)
    }

    // MARK: - moveIconInZone()

    @Test func moveIconInZone_movesWithinToolZone() {
        var icons = [
            ToolbarIcon.toolIcon(.pen),
            ToolbarIcon.toolIcon(.eraser),
            ToolbarIcon.toolIcon(.highlighter),
            ToolbarIcon.colorIcon(.red, colorScheme: .light),
        ]
        let penID = icons[0].id

        icons.moveIconInZone(id: penID, toZoneIndex: 2, isColor: false)

        // Pen should now be after highlighter
        let penIndex = icons.firstIndex(where: { $0.id == penID })!
        let highlighterIndex = icons.firstIndex(where: { $0.type == .highlighter })!
        #expect(penIndex > highlighterIndex)
    }

    @Test func moveIconInZone_movesWithinColorZone() {
        var icons = [
            ToolbarIcon.toolIcon(.pen),
            ToolbarIcon.colorIcon(.red, name: "Red", colorScheme: .light),
            ToolbarIcon.colorIcon(.blue, name: "Blue", colorScheme: .light),
            ToolbarIcon.colorIcon(.green, name: "Green", colorScheme: .light),
        ]
        let redID = icons[1].id

        icons.moveIconInZone(id: redID, toZoneIndex: 2, isColor: true)

        // Red should now be after green
        let redIndex = icons.firstIndex(where: { $0.id == redID })!
        let greenIndex = icons.firstIndex(where: { $0.name == "Green" })!
        #expect(redIndex > greenIndex)
    }

    @Test func moveIconInZone_clampsToZoneBounds() {
        var icons = [
            ToolbarIcon.toolIcon(.pen),
            ToolbarIcon.toolIcon(.eraser),
            ToolbarIcon.colorIcon(.red, colorScheme: .light),
        ]
        let penID = icons[0].id

        // Target way beyond bounds
        icons.moveIconInZone(id: penID, toZoneIndex: 100, isColor: false)

        // Should still be in the array and remain a tool icon
        #expect(icons.contains(where: { $0.id == penID }))
        #expect(icons.count == 3)
    }
}
