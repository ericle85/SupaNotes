import Testing
import SwiftUI
@testable import SupaNotes

/// Tests for the IconDragState class
/// This tests the logic for tracking when a user drags toolbar icons around
/// and calculating how other icons should move to make room
@MainActor
@Suite struct IconDragStateTests {

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

    // Helper: two tool icons (pen, eraser)
    private func makeToolIcons() -> [ToolbarIcon] {
        [
            ToolbarIcon.toolIcon(.pen),
            ToolbarIcon.toolIcon(.eraser),
        ]
    }

    // Helper: three color icons
    private func makeColorIcons() -> [ToolbarIcon] {
        [
            ToolbarIcon.colorIcon(.red),
            ToolbarIcon.colorIcon(.blue),
            ToolbarIcon.colorIcon(.green),
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
        state.proposedZoneIndex = 1
        state.dragZoneIsColor = false

        // Eraser (index 1) is at proposed position, should shift backward
        let displacement = state.reorderDisplacement(for: tools[1], toolIcons: tools, colorIcons: colors, slotPitch: 50)
        #expect(displacement == -50)
    }

    @Test func reorderDisplacement_backwardDrag_shiftsForward() {
        let tools = makeToolIcons()
        let colors = makeColorIcons()
        let state = IconDragState()
        state.draggedIconID = tools[1].id
        state.dragStartZoneIndex = 1
        state.proposedZoneIndex = 0
        state.dragZoneIsColor = false

        // Pen (index 0) is between proposed (0) and start (1), should shift forward
        let displacement = state.reorderDisplacement(for: tools[0], toolIcons: tools, colorIcons: colors, slotPitch: 50)
        #expect(displacement == 50)
    }

    @Test func reorderDisplacement_wrongZone_returnsZero() {
        let tools = makeToolIcons()
        let colors = makeColorIcons()
        let state = IconDragState()
        state.draggedIconID = tools[0].id
        state.dragStartZoneIndex = 0
        state.proposedZoneIndex = 1
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
            ToolbarIcon.colorIcon(.red),
        ]
        let penID = icons[0].id

        // Move pen to position 1 within the tool zone
        icons.moveIconInZone(id: penID, toZoneIndex: 1, isColor: false)

        let penIndex = icons.firstIndex(where: { $0.id == penID })!
        let eraserIndex = icons.firstIndex(where: { $0.type == .eraser })!
        // Pen should now be after eraser
        #expect(penIndex > eraserIndex)
    }

    @Test func moveIconInZone_movesWithinColorZone() {
        var icons = [
            ToolbarIcon.toolIcon(.pen),
            ToolbarIcon.colorIcon(.red, name: "Red"),
            ToolbarIcon.colorIcon(.blue, name: "Blue"),
            ToolbarIcon.colorIcon(.green, name: "Green"),
        ]
        let redID = icons[1].id

        // Move red to position 2 within the color zone
        icons.moveIconInZone(id: redID, toZoneIndex: 2, isColor: true)

        let redIndex = icons.firstIndex(where: { $0.id == redID })!
        let greenIndex = icons.firstIndex(where: { $0.name == "Green" })!
        // Red should now be after green
        #expect(redIndex > greenIndex)
    }

    @Test func moveIconInZone_clampsToZoneBounds() {
        var icons = [
            ToolbarIcon.toolIcon(.pen),
            ToolbarIcon.toolIcon(.eraser),
            ToolbarIcon.colorIcon(.red),
        ]
        let penID = icons[0].id

        // Try to move pen to position 100 (way beyond actual positions)
        icons.moveIconInZone(id: penID, toZoneIndex: 100, isColor: false)

        #expect(icons.contains(where: { $0.id == penID }))
        #expect(icons.count == 3)
    }
}
