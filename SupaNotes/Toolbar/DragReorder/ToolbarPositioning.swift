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
        toolbarEdge: Binding<String>
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
                DispatchQueue.main.asyncAfter(deadline: .now() + Design.Drag.repositionDelay) {
                    didRepositionToolbar.wrappedValue = false
                }

                let screenSize = UIScreen.main.bounds.size
                let loc = value.location
                let distTop = loc.y
                let distBottom = screenSize.height - loc.y
                let distLeft = loc.x
                let distRight = screenSize.width - loc.x
                let minDist = min(distTop, distBottom, distLeft, distRight)

                withAnimation(.spring(response: Design.Animation.springResponse, dampingFraction: Design.Animation.springDamping)) {
                    if minDist == distTop {
                        toolbarEdge.wrappedValue = "top"
                    } else if minDist == distBottom {
                        toolbarEdge.wrappedValue = "bottom"
                    } else if minDist == distLeft {
                        toolbarEdge.wrappedValue = "left"
                    } else {
                        toolbarEdge.wrappedValue = "right"
                    }
                }
            }
    }
}
