import SwiftUI
import UIKit

struct GhostOverlayView: View {
    let tokens: [OverlayToken]
    let latexImages: [UUID: UIImage]

    var body: some View {
        if !tokens.isEmpty {
            VStack {
                Spacer()
                HStack(alignment: .center, spacing: 4) {
                    ForEach(tokens) { token in
                        switch token.type {
                        case .word:
                            Text(token.value)
                                .font(.system(size: 28, design: .serif))
                                .foregroundColor(Color(.darkGray))
                        case .latex:
                            if let img = latexImages[token.id] {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 36)
                            } else {
                                Text(token.value)
                                    .font(.system(size: 20, design: .serif))
                                    .italic()
                            }
                        }
                    }
                }
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
}
