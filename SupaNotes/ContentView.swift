import SwiftUI

struct ContentView: View {
    var body: some View {
        CanvasView()
            .ignoresSafeArea()
            .preferredColorScheme(.light)
    }
}

#Preview {
    ContentView()
}
