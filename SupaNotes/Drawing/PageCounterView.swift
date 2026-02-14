import SwiftUI

struct PageCounterView: View {
    let currentPage: Int
    let totalPages: Int

    var body: some View {
        Text("Page \(currentPage + 1) of \(totalPages)")
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color("ToolbarBackground"))
                    .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 1)
            )
    }
}
