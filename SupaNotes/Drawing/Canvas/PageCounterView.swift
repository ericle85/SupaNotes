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
                RoundedRectangle(cornerRadius: Design.CornerRadius.small)
                    .fill(Color("ToolbarBackground"))
                    .shadow(
                        color: .black.opacity(Design.Shadow.subtle.color),
                        radius: Design.Shadow.subtle.radius,
                        x: Design.Shadow.subtle.x,
                        y: Design.Shadow.subtle.y
                    )
            )
    }
}
