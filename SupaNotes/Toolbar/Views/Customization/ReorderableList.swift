import SwiftUI

struct ReorderableList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    let isEditing: Bool
    let rowHeight: CGFloat
    let spacing: CGFloat
    let onMove: (_ fromID: Item.ID, _ toIndex: Int) -> Void
    var onDragChange: ((Item.ID?) -> Void)? = nil
    @ViewBuilder let row: (Item) -> Row

    @State private var draggedID: Item.ID?
    @State private var dragTranslation: CGFloat = 0
    @State private var startIndex: Int?
    @State private var proposedIndex: Int?

    private var pitch: CGFloat {
        rowHeight + spacing
    }

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                rowView(for: item, at: idx)
            }
        }
    }

    private func rowView(for item: Item, at idx: Int) -> some View {
        let isDragged = draggedID == item.id
        let displacement = displacement(for: idx, draggedID: draggedID)
        return HStack(spacing: 10) {
            if isEditing {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: rowHeight)
                    .contentShape(Rectangle())
                    .highPriorityGesture(dragGesture(item: item))
            }
            row(item)
        }
        .frame(height: rowHeight)
        .wiggle(enabled: isEditing && !isDragged, seed: idx)
        .scaleEffect(isDragged ? 1.1 : 1)
        .shadow(color: isDragged ? .black.opacity(0.2) : .clear, radius: 6, y: 3)
        .offset(y: isDragged ? dragTranslation : displacement)
        .transaction { if isDragged { $0.animation = nil } }
        .zIndex(isDragged ? 100 : 0)
    }

    private func displacement(for myIdx: Int, draggedID: Item.ID?) -> CGFloat {
        guard let s = startIndex, let p = proposedIndex, s != p, draggedID != nil else { return 0 }
        if items[myIdx].id == draggedID { return 0 }
        if s < p {
            if myIdx > s && myIdx <= p { return -pitch }
        } else {
            if myIdx >= p && myIdx < s { return pitch }
        }
        return 0
    }

    private func dragGesture(item: Item) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                let t = value.translation.height
                if draggedID != item.id {
                    draggedID = item.id
                    onDragChange?(item.id)
                    let idx = items.firstIndex(where: { $0.id == item.id }) ?? 0
                    startIndex = idx
                    proposedIndex = idx
                }
                dragTranslation = t

                guard let s = startIndex, let cur = proposedIndex else { return }
                let target = s + Int((t / pitch).rounded())
                let clamped = max(0, min(target, items.count - 1))
                if clamped != cur {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.78)) {
                        proposedIndex = clamped
                    }
                }
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                    if let s = startIndex, let p = proposedIndex, s != p, let id = draggedID {
                        onMove(id, p)
                    }
                    draggedID = nil
                    dragTranslation = 0
                }
                onDragChange?(nil)
                startIndex = nil
                proposedIndex = nil
            }
    }
}

// MARK: - Wiggle

struct WiggleModifier: ViewModifier {
    let enabled: Bool
    let seed: Int

    func body(content: Content) -> some View {
        let amp: CGFloat = seed.isMultiple(of: 2) ? 1.2 : -1.2
        content.phaseAnimator([false, true]) { view, phase in
            view.offset(y: enabled ? (phase ? amp : -amp) : 0)
        } animation: { _ in .easeInOut(duration: 0.16) }
    }
}

extension View {
    func wiggle(enabled: Bool, seed: Int) -> some View {
        modifier(WiggleModifier(enabled: enabled, seed: seed))
    }
}
