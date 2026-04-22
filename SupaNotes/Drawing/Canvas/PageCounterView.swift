import SwiftUI
// MARK: - Page Counter

/// Small floating label that shows "current page / total pages".
struct PageCounterView: View {
    let currentPage: Int // Index of the current page (0-based) which will converted to display the page number (1-based).
    let totalPages: Int // Total number of pages in the document.

    /// SwiftUI view body.
    var body: some View {
        // Display page count in human-readable form (1-based).
        Text("Page \(currentPage + 1) of \(totalPages)")
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                // Add rounded background with subtle shadow.
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
