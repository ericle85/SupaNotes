import SwiftUI

struct AgentControlBar: View {
    let state: AgentRegionState

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                content
                    .padding(.trailing, 20)
                    .padding(.bottom, 100)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state.phase {
        case .idle:
            Button { state.startSelection() } label: {
                Label("Select Region", systemImage: "viewfinder.circle")
                    .capsuleButton()
            }

        case .awaitingFirstPoint:
            Label("Tap first corner", systemImage: "1.circle.fill")
                .capsuleButton()

        case .awaitingSecondPoint:
            Label("Tap second corner", systemImage: "2.circle.fill")
                .capsuleButton()

        case .regionSelected:
            HStack(spacing: 10) {
                Button { state.clear() } label: {
                    Text("Clear Overlay").capsuleButton()
                }
                Button { state.startNewOverlay() } label: {
                    Text("New Overlay").capsuleButton()
                }
            }
        }
    }
}

private extension View {
    func capsuleButton() -> some View {
        self
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial)
            .clipShape(Capsule())
    }
}
