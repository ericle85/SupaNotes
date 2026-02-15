import Testing
import SwiftUI
@testable import SupaNotes

/// Tests for the IconDragState class
/// This tests the logic for tracking when a user drags toolbar icons around
/// and calculating how other icons should move to make room
@MainActor
struct IconDragStateTests {

    // MARK: - reset()
    // Tests that the reset() function clears all drag-related state

    @Test func reset_clearsAllProperties() {
        // Create a state with all properties set to something
        let state = IconDragState()
        state.draggedIconID = UUID()
        state.dragTranslation = CGSize(width: 100, height: 50)
        state.isDraggingOutOfBounds = true
        state.dragStartZoneIndex = 2
        state.proposedZoneIndex = 4
        state.dragZoneIsColor = true

        // Call reset to clear everything
        state.reset(animated: false)

        // After reset, all values should be cleared/reset to default
        #expect(state.draggedIconID == nil)              // No icon being dragged
        #expect(state.dragTranslation == .zero)          // No movement
        #expect(state.isDraggingOutOfBounds == false)    // Not out of bounds
        #expect(state.dragStartZoneIndex == nil)         // No start position
        #expect(state.proposedZoneIndex == nil)          // No target position
        #expect(state.dragZoneIsColor == false)          // Not dragging in color zone
    }

    // MARK: - reorderDisplacement()
    // Tests that calculate how much other icons should move when one icon is dragged
    // This creates the "sliding" effect where icons move out of the way

    // Helper function to create a simple set of tool icons (pen, eraser, highlighter)
    private func makeToolIcons() -> [ToolbarIcon] {
        [
            ToolbarIcon.toolIcon(.pen),
            ToolbarIcon.toolIcon(.eraser),
            ToolbarIcon.toolIcon(.highlighter),
        ]
    }

    // Helper function to create a simple set of color icons (red, blue, green)
    private func makeColorIcons() -> [ToolbarIcon] {
        [
            ToolbarIcon.colorIcon(.red, colorScheme: .light),
            ToolbarIcon.colorIcon(.blue, colorScheme: .light),
            ToolbarIcon.colorIcon(.green, colorScheme: .light),
        ]
    }

    @Test func reorderDisplacement_noDrag_returnsZero() {
        // When no drag is happening, no icon should move
        let state = IconDragState()
        let tools = makeToolIcons()
        let colors = makeColorIcons()
        let displacement = state.reorderDisplacement(for: tools[0], toolIcons: tools, colorIcons: colors, slotPitch: 50)
        #expect(displacement == 0)  // No movement
    }

    @Test func reorderDisplacement_forwardDrag_shiftsBackward() {
        // When dragging the first tool forward (from index 0 to 2),
        // the icons in between should shift backward
        let tools = makeToolIcons()
        let colors = makeColorIcons()
        let state = IconDragState()
        state.draggedIconID = tools[0].id           // Dragging the pen
        state.dragStartZoneIndex = 0                // From position 0
        state.proposedZoneIndex = 2                 // To position 2
        state.dragZoneIsColor = false               // In the tool zone

        // Icon at index 1 (eraser) is between start (0) and proposed (2), should shift backward
        let displacement = state.reorderDisplacement(for: tools[1], toolIcons: tools, colorIcons: colors, slotPitch: 50)
        #expect(displacement == -50)  // Move backward by one slot (50 pixels)
    }

    @Test func reorderDisplacement_forwardDrag_endIcon_shiftsBackward() {
        // The icon at the destination should also shift backward
        let tools = makeToolIcons()
        let colors = makeColorIcons()
        let state = IconDragState()
        state.draggedIconID = tools[0].id           // Dragging the pen
        state.dragStartZoneIndex = 0                // From position 0
        state.proposedZoneIndex = 2                 // To position 2
        state.dragZoneIsColor = false               // In the tool zone

        // Icon at index 2 (highlighter) is at the proposed position, should also shift backward
        let displacement = state.reorderDisplacement(for: tools[2], toolIcons: tools, colorIcons: colors, slotPitch: 50)
        #expect(displacement == -50)  // Move backward by one slot (50 pixels)
    }

    @Test func reorderDisplacement_backwardDrag_shiftsForward() {
        // When dragging backward, icons between should shift forward
        let tools = makeToolIcons()
        let colors = makeColorIcons()
        let state = IconDragState()
        state.draggedIconID = tools[2].id           // Dragging the highlighter
        state.dragStartZoneIndex = 2                // From position 2
        state.proposedZoneIndex = 0                 // To position 0
        state.dragZoneIsColor = false               // In the tool zone

        // Icon at index 1 (eraser) is between proposed (0) and start (2), should shift forward
        let displacement = state.reorderDisplacement(for: tools[1], toolIcons: tools, colorIcons: colors, slotPitch: 50)
        #expect(displacement == 50)  // Move forward by one slot (50 pixels)
    }

    @Test func reorderDisplacement_outsideRange_returnsZero() {
        // Icons outside the drag range should not move
        let tools = makeToolIcons()
        let colors = makeColorIcons()
        let state = IconDragState()
        state.draggedIconID = tools[0].id           // Dragging the pen
        state.dragStartZoneIndex = 0                // From position 0
        state.proposedZoneIndex = 1                 // To position 1
        state.dragZoneIsColor = false               // In the tool zone

        // Icon at index 2 is outside the drag range [0, 1], so it shouldn't move
        let displacement = state.reorderDisplacement(for: tools[2], toolIcons: tools, colorIcons: colors, slotPitch: 50)
        #expect(displacement == 0)  // No movement
    }

    @Test func reorderDisplacement_wrongZone_returnsZero() {
        // Color icons should not move when dragging in the tool zone
        let tools = makeToolIcons()
        let colors = makeColorIcons()
        let state = IconDragState()
        state.draggedIconID = tools[0].id           // Dragging the pen
        state.dragStartZoneIndex = 0                // From position 0
        state.proposedZoneIndex = 2                 // To position 2
        state.dragZoneIsColor = false               // In the tool zone

        // Color icon should not be displaced by a tool zone drag
        let displacement = state.reorderDisplacement(for: colors[1], toolIcons: tools, colorIcons: colors, slotPitch: 50)
        #expect(displacement == 0)  // No movement
    }

    // MARK: - moveIconInZone()
    // Tests for actually moving an icon to a new position within its zone

    @Test func moveIconInZone_movesWithinToolZone() {
        // Set up an array with 3 tool icons and 1 color icon
        var icons = [
            ToolbarIcon.toolIcon(.pen),
            ToolbarIcon.toolIcon(.eraser),
            ToolbarIcon.toolIcon(.highlighter),
            ToolbarIcon.colorIcon(.red, colorScheme: .light),
        ]
        let penID = icons[0].id  // Remember the pen's ID

        // Move the pen to position 2 within the tool zone
        icons.moveIconInZone(id: penID, toZoneIndex: 2, isColor: false)

        // Find where the pen ended up
        let penIndex = icons.firstIndex(where: { $0.id == penID })!
        let highlighterIndex = icons.firstIndex(where: { $0.type == .highlighter })!
        // Pen should now be after highlighter
        #expect(penIndex > highlighterIndex)
    }

    @Test func moveIconInZone_movesWithinColorZone() {
        // Set up an array with 1 tool icon and 3 color icons
        var icons = [
            ToolbarIcon.toolIcon(.pen),
            ToolbarIcon.colorIcon(.red, name: "Red", colorScheme: .light),
            ToolbarIcon.colorIcon(.blue, name: "Blue", colorScheme: .light),
            ToolbarIcon.colorIcon(.green, name: "Green", colorScheme: .light),
        ]
        let redID = icons[1].id  // Remember the red color's ID

        // Move red to position 2 within the color zone
        icons.moveIconInZone(id: redID, toZoneIndex: 2, isColor: true)

        // Find where red ended up
        let redIndex = icons.firstIndex(where: { $0.id == redID })!
        let greenIndex = icons.firstIndex(where: { $0.name == "Green" })!
        // Red should now be after green
        #expect(redIndex > greenIndex)
    }

    @Test func moveIconInZone_clampsToZoneBounds() {
        // Test that trying to move an icon to an impossible position handles it gracefully
        var icons = [
            ToolbarIcon.toolIcon(.pen),
            ToolbarIcon.toolIcon(.eraser),
            ToolbarIcon.colorIcon(.red, colorScheme: .light),
        ]
        let penID = icons[0].id

        // Try to move pen to position 100 (way beyond the actual positions)
        icons.moveIconInZone(id: penID, toZoneIndex: 100, isColor: false)

        // The icon should still exist and the array size shouldn't change
        #expect(icons.contains(where: { $0.id == penID }))  // Pen is still there
        #expect(icons.count == 3)                            // Array size didn't change
    }
}
