import SwiftUI

// MARK: - Drag-to-Reorder State

@Observable
final class IconDragState {
    var draggedIconID: UUID?
    var dragTranslation: CGSize = .zero
    var isDraggingOutOfBounds = false
    var dragStartZoneIndex: Int?
    var proposedZoneIndex: Int?
    var dragZoneIsColor: Bool = false

    func reset(animated: Bool = true) {
        dragStartZoneIndex = nil
        proposedZoneIndex = nil
        dragZoneIsColor = false

        if animated {
            withAnimation(.spring(response: Design.Animation.springResponse, dampingFraction: 0.82)) {
                draggedIconID = nil
                dragTranslation = .zero
                isDraggingOutOfBounds = false
            }
        } else {
            draggedIconID = nil
            dragTranslation = .zero
            isDraggingOutOfBounds = false
        }
    }

    func reorderDisplacement(for icon: ToolbarIcon, toolIcons: [ToolbarIcon], colorIcons: [ToolbarIcon], slotPitch: CGFloat) -> CGFloat {
        guard let dragID = draggedIconID, dragID != icon.id,
              let startIdx = dragStartZoneIndex,
              let proposed = proposedZoneIndex,
              startIdx != proposed else { return 0 }

        let isColor = icon.type == .color
        guard isColor == dragZoneIsColor else { return 0 }

        let zone = isColor ? colorIcons : toolIcons
        guard let myIdx = zone.firstIndex(where: { $0.id == icon.id }) else { return 0 }

        if startIdx < proposed {
            if myIdx > startIdx && myIdx <= proposed { return -slotPitch }
        } else {
            if myIdx >= proposed && myIdx < startIdx { return slotPitch }
        }
        return 0
    }
}

// MARK: - Reorder Commit

extension Array where Element == ToolbarIcon {
    mutating func moveIconInZone(id: UUID, toZoneIndex target: Int, isColor: Bool) {
        guard let currentFlatIndex = firstIndex(where: { $0.id == id }) else { return }
        let icon = remove(at: currentFlatIndex)
        let newZoneIndices = indices.filter {
            isColor ? self[$0].type == .color : self[$0].type != .color
        }
        let clampedTarget = Swift.min(Swift.max(target, 0), newZoneIndices.count)
        let insertAt: Int
        if clampedTarget >= newZoneIndices.count {
            if let last = newZoneIndices.last {
                insertAt = last + 1
            } else {
                insertAt = isColor ? count : 0
            }
        } else {
            insertAt = newZoneIndices[clampedTarget]
        }
        insert(icon, at: insertAt)
    }
}
