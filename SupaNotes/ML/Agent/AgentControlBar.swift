import SwiftUI

struct AgentControlBar: View {
    let state: AgentRegionState
    var captureToken: AgentCaptureToken?
    var sender: AgentVisionSender?

    var body: some View {
        VStack {
            Spacer()
            HStack {
                // Debug: send current page to vision server
                sendButton
                    .padding(.leading, 20)
                    .padding(.bottom, 100)
                Spacer()
                content
                    .padding(.trailing, 20)
                    .padding(.bottom, 100)
            }
        }
    }

    @ViewBuilder
    private var sendButton: some View {
        if let sender, let token = captureToken {
            Button {
                if let image = token.captureCurrentPage?(state.selectedRect) {
                    sender.send(image)
                }
            } label: {
                sendLabel(for: sender.status)
            }
            .disabled({
                if case .sending = sender.status { return true }
                return false
            }())
        }
    }

    @ViewBuilder
    private func sendLabel(for status: AgentVisionSender.Status) -> some View {
        switch status {
        case .idle:
            Label("Send View", systemImage: "eye.circle")
                .capsuleButton()
        case .sending:
            Label("Sending…", systemImage: "arrow.up.circle")
                .capsuleButton()
        case .sent:
            Label("Sent", systemImage: "checkmark.circle.fill")
                .capsuleButton()
                .foregroundStyle(.green)
        case .failed(let msg):
            Label(msg, systemImage: "xmark.circle.fill")
                .capsuleButton()
                .foregroundStyle(.red)
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
