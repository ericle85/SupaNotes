import SwiftData
import SwiftUI

/// Temporary scaffolding screen used to prove out the agent-QA loop:
/// three buttons that each display their number on tap. Every interactive
/// element carries a stable `accessibilityIdentifier` so UI tests (and the
/// agents that write them) can find and drive it deterministically.
struct ContentView: View {
    @State private var displayed: String = "—"

    var body: some View {
        VStack(spacing: 40) {
            Text(displayed)
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .monospacedDigit()
                .accessibilityIdentifier(QAID.displayedNumber)

            HStack(spacing: 24) {
                ForEach(1...3, id: \.self) { number in
                    Button("\(number)") {
                        displayed = "\(number)"
                    }
                    .font(.system(size: 40, weight: .semibold))
                    .frame(width: 100, height: 100)
                    .background(.tint, in: RoundedRectangle(cornerRadius: 20))
                    .foregroundStyle(.white)
                    .accessibilityIdentifier(QAID.numberButton(number))
                }
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
