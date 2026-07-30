import SwiftUI

struct ContentView: View {
    @StateObject private var canvasController = DrawingCanvasController()
    @StateObject private var ocrEngine = OCREngine()
    @State private var exportAlert: ExportAlert?
    @State private var selectedBlockID: String?

    var body: some View {
        HStack(spacing: 0) {
            canvasColumn
            resultsPanel
        }
        .onAppear { setupStrokeHandler() }
        .onChange(of: selectedBlockID) { _ in updateSelectedBlockBBox() }
        .onChange(of: ocrEngine.blocks) { _ in updateSelectedBlockBBox() }
        .alert(item: $exportAlert) { alert in exportAlertView(alert) }
        .preferredColorScheme(.light)
    }

    private var canvasColumn: some View {
        ZStack {
            Color(.systemGray5)
                .ignoresSafeArea()

            CanvasView(controller: canvasController)
                .frame(width: LetterPageSize.width, height: LetterPageSize.height)
                .shadow(radius: 4)

            canvasActionBar
        }
    }

    private var canvasActionBar: some View {
        VStack(alignment: .trailing, spacing: 12) {
            Button("Save OCR Fixture") { saveOCRFixture() }
                .buttonStyle(.borderedProminent)

            Button("Clear", action: clearCanvas)
                .buttonStyle(.bordered)
                .accessibilityIdentifier(QAID.clearStrokes)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    private var resultsPanel: some View {
        OCRResultsPanel(
            blocks: ocrEngine.blocks,
            isReady: ocrEngine.isModelReady,
            selectedBlockID: $selectedBlockID
        )
        .frame(width: 300)
    }

    private func setupStrokeHandler() {
        canvasController.onStrokesChanged = { strokes in
            ocrEngine.strokesChanged(strokes)
        }
    }

    private func updateSelectedBlockBBox() {
        guard let selectedBlockID else {
            canvasController.selectedBlockBBox = nil
            return
        }
        canvasController.selectedBlockBBox = ocrEngine.blocks.first { $0.id == selectedBlockID }?.bbox
    }

    private func clearCanvas() {
        canvasController.clear()
        ocrEngine.blocks = []
        selectedBlockID = nil
        canvasController.selectedBlockBBox = nil
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

    private func exportAlertView(_ alert: ExportAlert) -> Alert {
        Alert(
            title: Text(alert.title),
            message: Text(alert.message),
            dismissButton: .default(Text("OK"))
        )
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
