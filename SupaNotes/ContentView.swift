import SwiftUI

struct ContentView: View {
    @StateObject private var canvasController = DrawingCanvasController()
    @StateObject private var ocrEngine = OCREngine()
    @State private var exportAlert: ExportAlert?

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Color(.systemGray5)
                    .ignoresSafeArea()

                CanvasView(controller: canvasController)
                    .frame(width: LetterPageSize.width, height: LetterPageSize.height)
                    .shadow(radius: 4)

                VStack(alignment: .trailing, spacing: 12) {
                    Button("Save OCR Fixture") { saveOCRFixture() }
                        .buttonStyle(.borderedProminent)

                    Button("Clear") {
                        canvasController.clear()
                        ocrEngine.blocks = []
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier(QAID.clearStrokes)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }

            OCRResultsPanel(blocks: ocrEngine.blocks, isReady: ocrEngine.isModelReady)
                .frame(width: 300)
        }
        .onAppear {
            canvasController.onStrokesChanged = { strokes in
                ocrEngine.strokesChanged(strokes)
            }
        }
        .alert(item: $exportAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .preferredColorScheme(.light)
    }

    private func saveOCRFixture() {
        do {
            let directoryURL = try canvasController.saveOCRFixture()
            let savedFiles = "Saved strokes.json, rendered.png, and notes.md to:"
            exportAlert = ExportAlert(
                title: "OCR Fixture Saved",
                message: "\(savedFiles)\n\n\(directoryURL.path)"
            )
        } catch {
            exportAlert = ExportAlert(
                title: "Could Not Save Fixture",
                message: error.localizedDescription
            )
        }
    }
}

private struct ExportAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

#Preview {
    ContentView()
}
