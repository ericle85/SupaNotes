import SwiftUI
import UIKit

struct GhostOverlayView: View {
    let tokens: [OverlayToken]
    let characters: [OverlayCharacter]
    let renderedImage: UIImage?
    let renderSize: CGSize

    var body: some View {
        if !tokens.isEmpty {
            VStack {
                Spacer()
                overlayContent
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                    .opacity(0.7)
                    .padding(.bottom, 100)
            }
            .allowsHitTesting(false)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    @ViewBuilder
    private var overlayContent: some View {
        if let renderedImage {
            // Debug boxes are baked into the image by JS
            Image(uiImage: renderedImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 500, maxHeight: 300)
        } else {
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
