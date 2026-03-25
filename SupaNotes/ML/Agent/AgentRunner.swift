import UIKit

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
                // 1. Capture birds-eye page image
                status = .capturing
                guard let pageImage = captureToken.captureCurrentPage?(nil) else {
                    status = .failed("Capture failed")
                    return
                }

                // 2. Send raw page image to debug server for preview
                sender.send(pageImage)

                // 3. Ask model for a normalized tap point (0–1 in each axis)
                status = .thinking
                let normalizedPoint = try await client.selectTapPoint(image: pageImage)

                // 4. Convert normalized → image space (612×792), then → screen-space crop box
                let imagePoint = CGPoint(
                    x: normalizedPoint.x * 612,
                    y: normalizedPoint.y * 792
                )
                let boxW: CGFloat = 120
                let boxH: CGFloat = 40
                let imageRect = CGRect(
                    x: imagePoint.x - boxW / 2,
                    y: imagePoint.y - boxH / 2,
                    width: boxW,
                    height: boxH
                )
                let screenRect = captureToken.imageRectToScreenRect?(imageRect) ?? imageRect
                regionState.phase = .regionSelected(screenRect)

                // 5. Re-capture with annotation and send to debug server
                if let annotated = captureToken.captureCurrentPage?(screenRect) {
                    sender.send(annotated)
                }

                status = .done
                // Auto-reset
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
