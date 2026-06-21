import SwiftUI

struct DrawingDemoView: View {
    @StateObject private var controller = PencilCanvasController()
    @State private var command = ""

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Strokes: \(controller.strokeCount)")
                    .font(.headline)
                    .accessibilityIdentifier(QAID.strokeCount)
                Spacer()
                Button("Clear") { controller.clear() }
                    .accessibilityIdentifier(QAID.clearStrokes)
            }
            .padding(.horizontal)

            Text("Last touch — \(controller.lastTouchInfo)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(QAID.touchType)

            if QAEnvironment.isUITestMode {
                HStack {
                    TextField("x,y x,y", text: $command)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier(QAID.pencilBridgeCommand)
                    Button("Inject") {
                        controller.inject(command: command)
                        command = ""
                    }
                    .accessibilityIdentifier(QAID.pencilBridgeInject)
                }
                .padding(.horizontal)
            }

            PencilCanvas(controller: controller)
        }
        .padding(.vertical)
        .navigationTitle("Drawing")
        .explicitBack()
    }
}

#Preview { DrawingDemoView() }
