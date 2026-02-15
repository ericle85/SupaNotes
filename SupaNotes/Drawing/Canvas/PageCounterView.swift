import SwiftUI

struct PageCounterView: View {
    let currentPage: Int
    let totalPages: Int

    var body: some View {
        Text("Page \(currentPage + 1) of \(totalPages)")
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
            .roundedButton(
                background: .customColor("ToolbarBackground"),
                padding: .compact,
                shadow: Design.Shadow.subtle
            )
    }
}

#Preview {
    VStack(spacing: 20) {
        PageCounterView(currentPage: 1, totalPages: 1)
        PageCounterView(currentPage: 5, totalPages: 12)
        PageCounterView(currentPage: 100, totalPages: 100)
    }
    .padding()
    .background(Color.gray.opacity(0.2))
}
