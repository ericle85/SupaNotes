import UIKit
import PencilKit

@Observable
final class AgentRunner {
    enum Status {
        case idle
        case capturing
        case thinking
        case done
        case failed(String)
    }

    var status: Status = .idle

    private let client = AgentOllamaClient()

    func run(
        captureToken: AgentCaptureToken,
        regionState: AgentRegionState,
        sender: AgentVisionSender
    ) {
        Task { @MainActor in
            do {
                // 1. Capture page image + strokes
                status = .capturing
                guard let pageImage = captureToken.captureCurrentPage?(nil) else {
                    status = .failed("Capture failed")
                    return
                }
                guard let drawing = captureToken.currentPageDrawing?(),
                      !drawing.strokes.isEmpty else {
                    status = .failed("No strokes on page")
                    try? await Task.sleep(for: .seconds(2))
                    if case .failed = status { status = .idle }
                    return
                }

                guard let strokesJSON = AgentStrokeSerializer.jsonString(drawing: drawing) else {
                    status = .failed("Stroke serialization failed")
                    try? await Task.sleep(for: .seconds(2))
                    if case .failed = status { status = .idle }
                    return
                }

                sender.send(pageImage)
                print("[AgentRunner] strokes JSON: \(strokesJSON.prefix(500))")

                // 2. Ask model to select a region using image + stroke coordinates
                status = .thinking
                let imageRect = try await client.selectRegion(image: pageImage, strokesJSON: strokesJSON)

                // 3. Convert to screen space and show
                let screenRect = captureToken.imageRectToScreenRect?(imageRect) ?? imageRect
                regionState.phase = .regionSelected(screenRect)

                if let annotated = captureToken.captureCurrentPage?(screenRect) {
                    sender.send(annotated)
                }

                status = .done
                try? await Task.sleep(for: .seconds(2))
                if case .done = status { status = .idle }

            } catch {
                status = .failed(error.localizedDescription)
                try? await Task.sleep(for: .seconds(3))
                if case .failed = status { status = .idle }
            }
        }
    }
}
