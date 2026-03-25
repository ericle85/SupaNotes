import SwiftUI

enum AgentSelectionPhase {
    case idle
    case awaitingFirstPoint
    case awaitingSecondPoint(CGPoint)
    case regionSelected(CGRect)
}

@Observable
final class AgentRegionState {
    var phase: AgentSelectionPhase = .idle

    var isActive: Bool {
        if case .idle = phase { return false }
        return true
    }

    var selectedRect: CGRect? {
        if case .regionSelected(let rect) = phase { return rect }
        return nil
    }

    var firstPoint: CGPoint? {
        if case .awaitingSecondPoint(let p) = phase { return p }
        return nil
    }

    func startSelection() { phase = .awaitingFirstPoint }

    func handleTap(_ point: CGPoint) {
        switch phase {
        case .awaitingFirstPoint:
            phase = .awaitingSecondPoint(point)
        case .awaitingSecondPoint(let first):
            phase = .regionSelected(CGRect(
                x: min(first.x, point.x),
                y: min(first.y, point.y),
                width: abs(point.x - first.x),
                height: abs(point.y - first.y)
            ))
        default:
            break
        }
    }

    func clear() { phase = .idle }
    func startNewOverlay() { phase = .awaitingFirstPoint }
}
