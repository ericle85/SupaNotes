import SwiftUI

struct ContentView: View {
    @StateObject private var canvasController = DrawingCanvasController()

    var body: some View {
        ZStack {
            Color(.systemGray5)
                .ignoresSafeArea()

            CanvasView(controller: canvasController)
                .frame(width: LetterPageSize.width, height: LetterPageSize.height)
                .shadow(radius: 4)

            Button("Clear") { canvasController.clear() }
                .buttonStyle(.borderedProminent)
                .padding()
                .accessibilityIdentifier(QAID.clearStrokes)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .preferredColorScheme(.light)
    }
}

#Preview {
    ContentView()
}
