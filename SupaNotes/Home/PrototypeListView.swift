import SwiftUI

struct PrototypeListView: View {
    @State private var navigateToOverlay = false

    var body: some View {
        List {
            NavigationLink("SwiftMath Gallery") {
                SwiftMathGalleryView()
            }
            NavigationLink("Overlay Fade Demo", isActive: $navigateToOverlay) {
                OverlayFadeDemoView()
            }
        }
        .navigationTitle("Prototypes")
        .onAppear { navigateToOverlay = true }
    }
}
