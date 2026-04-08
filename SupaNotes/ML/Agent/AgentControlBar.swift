import SwiftUI

struct AgentControlBar: View {
    var captureToken: AgentCaptureToken?
    var suggestionRunner: SuggestionRunner?

    var body: some View {
        VStack {
            Spacer()
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    suggestButton
                }
                .padding(.leading, 20)
                .padding(.bottom, 100)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var suggestButton: some View {
        if let suggestionRunner, let token = captureToken {
            Button {
                Task { await suggestionRunner.suggest(captureToken: token) }
            } label: {
                switch suggestionRunner.status {
                case .idle, .done:
                    Label("Suggest", systemImage: "text.bubble")
                        .capsuleButton()
                case .capturing:
                    Label("Capturing…", systemImage: "camera.circle")
                        .capsuleButton()
                case .thinking, .rendering:
                    Label("Thinking…", systemImage: "brain")
                        .capsuleButton()
                case .failed(let msg):
                    Label(msg.prefix(30).description, systemImage: "exclamationmark.circle")
                        .capsuleButton()
                        .foregroundStyle(.red)
                }
            }
            .disabled({
                switch suggestionRunner.status {
                case .capturing, .thinking: return true
                default: return false
                }
            }())
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
