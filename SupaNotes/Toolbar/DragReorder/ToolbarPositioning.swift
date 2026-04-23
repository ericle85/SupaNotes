import SwiftUI

// MARK: - Edge Snapping & Axis Helpers

struct ToolbarPositioning {
    @AppStorage("toolbarEdge") var toolbarEdge: String = "bottom"

    var edge: Edge {
        switch toolbarEdge {
        case "top": return .top
        case "left": return .leading
        case "right": return .trailing
        default: return .bottom
        }
    }

    var axis: Axis {
        edge == .top || edge == .bottom ? .horizontal : .vertical
    }

    var alignment: Alignment {
        switch edge {
        case .top: return .top
        case .bottom: return .bottom
        case .leading: return .leading
        case .trailing: return .trailing
        }
    }

    func mainAxisValue(_ size: CGSize) -> CGFloat {
        axis == .vertical ? size.height : size.width
    }

    func crossAxisValue(_ size: CGSize) -> CGFloat {
        axis == .vertical ? size.width : size.height
    }

    func mainAxisOffset(_ value: CGFloat) -> CGSize {
        axis == .vertical ? CGSize(width: 0, height: value) : CGSize(width: value, height: 0)
    }

    // MARK: - Repositioning Gesture

    static func repositionGesture(
        draggedIconID: UUID?,
        isDraggingToolbar: Binding<Bool>,
        didRepositionToolbar: Binding<Bool>,
        toolbarDragOffset: Binding<CGSize>,
        toolbarEdge: Binding<String>,
        screenSize: CGSize
    ) -> some Gesture {
        DragGesture(minimumDistance: Design.Drag.toolbarMinDragDistance, coordinateSpace: .global)
            .onChanged { value in
                guard draggedIconID == nil else { return }
                isDraggingToolbar.wrappedValue = true
                didRepositionToolbar.wrappedValue = true
                toolbarDragOffset.wrappedValue = value.translation
            }
            .onEnded { value in
                guard isDraggingToolbar.wrappedValue else { return }
                isDraggingToolbar.wrappedValue = false
                toolbarDragOffset.wrappedValue = .zero

                // Briefly disable interactions while the toolbar animates
                DispatchQueue.main.asyncAfter(deadline: .now() + Design.Drag.repositionDelay) {
                    didRepositionToolbar.wrappedValue = false
                }

                // Determine which edge of the screen is closest to the drag end location
                let loc = value.location
                let distances: [String: CGFloat] = [
                    "top": loc.y,
                    "bottom": screenSize.height - loc.y,
                    "left": loc.x,
                    "right": screenSize.width - loc.x,
                ]

                // Find the edge with the minimum distance
                if let closestEdge = distances.min(by: { $0.value < $1.value })?.key {
                    withAnimation(.spring(response: Design.Animation.springResponse, dampingFraction: Design.Animation.springDamping)) {
                        toolbarEdge.wrappedValue = closestEdge
                    }
                }
            }
    }
}
