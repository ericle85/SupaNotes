import SwiftUI

struct ExplicitBackButton: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Label("Back", systemImage: "chevron.backward")
                    }
                    .accessibilityIdentifier(QAID.backButton)
                }
            }
    }
}

extension View {
    func explicitBack() -> some View {
        modifier(ExplicitBackButton())
    }
}
