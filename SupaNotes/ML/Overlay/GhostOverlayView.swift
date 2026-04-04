import SwiftUI
import UIKit

/// Renders suggestion as a faded overlay at the bottom of the screen.
/// Uses KaTeX-rendered image for LaTeX, falls back to text if no image.
struct GhostOverlayView: View {
    let tokens: [OverlayToken]
    let renderedImage: UIImage?

    var body: some View {
        if !tokens.isEmpty {
            VStack {
                Spacer()
                overlayContent
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .opacity(0.7)
                    .padding(.bottom, 160)
            }
            .allowsHitTesting(false)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    @ViewBuilder
    private var overlayContent: some View {
        if let renderedImage {
            Image(uiImage: renderedImage)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 60)
        } else {
            // Fallback: plain text while rendering or on failure
            HStack(spacing: 4) {
                ForEach(tokens) { token in
                    Text(token.value)
                        .font(.system(size: 20, weight: .regular, design: token.type == .latex ? .serif : .default))
                        .italic(token.type == .latex)
                }
            }
        }
    }
}
