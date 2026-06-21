import SwiftData
import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Numbers (tap)") { NumbersDemoView() }
                    .accessibilityIdentifier(QAID.numbersLink)
                NavigationLink("Drawing (drag)") { DrawingDemoView() }
                    .accessibilityIdentifier(QAID.drawingLink)
                NavigationLink("Zoom & Scroll (pinch/pan)") { ZoomScrollDemoView() }
                    .accessibilityIdentifier(QAID.zoomScrollLink)
            }
            .navigationTitle("QA Demos")
        }
    }
}

#Preview {
    ContentView()
}
