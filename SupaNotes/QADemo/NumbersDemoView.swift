import SwiftUI

struct NumbersDemoView: View {
    @State private var displayed = "—"

    var body: some View {
        VStack(spacing: 40) {
            Text(displayed)
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .monospacedDigit()
                .accessibilityIdentifier(QAID.displayedNumber)

            HStack(spacing: 24) {
                ForEach(1 ... 3, id: \.self) { number in
                    Button("\(number)") { displayed = "\(number)" }
                        .font(.system(size: 40, weight: .semibold))
                        .frame(width: 100, height: 100)
                        .background(.tint, in: RoundedRectangle(cornerRadius: 20))
                        .foregroundStyle(.white)
                        .accessibilityIdentifier(QAID.numberButton(number))
                }
            }
        }
        .padding()
        .navigationTitle("Numbers")
        .explicitBack()
    }
}

#Preview { NumbersDemoView() }
