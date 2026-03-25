import SwiftUI

struct AgentRegionOverlayView: View {
    let state: AgentRegionState

    var body: some View {
        ZStack {
            if let first = state.firstPoint {
                Circle()
                    .fill(Color.blue.opacity(0.9))
                    .frame(width: 10, height: 10)
                    .position(first)
            }

            if let rect = state.selectedRect {
                Rectangle()
                    .fill(Color.blue.opacity(0.15))
                    .overlay(Rectangle().stroke(Color.blue.opacity(0.8), lineWidth: 2))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .allowsHitTesting(false)
    }
}
