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
    private let ctcModel: CTCModel? = try? CTCModel()

    func run(
        captureToken: AgentCaptureToken,
        regionState: AgentRegionState
    ) {
        Task { @MainActor in
            do {
                guard let screenRect = regionState.selectedRect else {
                    status = .failed("No region selected")
                    return
                }

                // 1. Capture cropped region
                status = .capturing
                guard let croppedImage = captureToken.captureCurrentPage?(screenRect) else {
                    status = .failed("Capture failed")
                    return
                }
                print("[AgentRunner] captured cropped region: \(croppedImage.size)")

                // 2. Classify: text vs math
                status = .thinking
                let contentType = try await client.classifyContent(image: croppedImage)
                print("[AgentRunner] classified as: \(contentType)")

                // 3. Run appropriate recognizer
                let result: String
                switch contentType {
                case .text:
                    result = try await AgentVisionRecognizer.recognizeText(in: croppedImage)
                case .math:
                    result = try recognizeWithCTC(captureToken: captureToken, regionState: regionState)
                }

                print("[AgentRunner] ===== RECOGNITION RESULT =====")
                print("[AgentRunner] type: \(contentType)")
                print("[AgentRunner] output: \(result)")
                print("[AgentRunner] ==============================")

                status = .done
                try? await Task.sleep(for: .seconds(2))
                if case .done = status { status = .idle }

            } catch {
                status = .failed(error.localizedDescription)
                print("[AgentRunner] error: \(error)")
                try? await Task.sleep(for: .seconds(3))
                if case .failed = status { status = .idle }
            }
        }
    }

    /// Use CTC model on strokes within the selected region.
    /// Same pipeline as demo: normalize all strokes together → extract features → predict.
    private func recognizeWithCTC(
        captureToken: AgentCaptureToken,
        regionState: AgentRegionState
    ) throws -> String {
        guard let model = ctcModel else {
            throw AgentError.parseError("CTC model not loaded")
        }
        guard let drawing = captureToken.currentPageDrawing?(),
              !drawing.strokes.isEmpty else {
            throw AgentError.parseError("No strokes")
        }
        guard let screenRect = regionState.selectedRect else {
            throw AgentError.parseError("No region")
        }

        let canvasRect = screenRectToCanvasRect(screenRect, captureToken: captureToken)
        let filteredStrokes = extractStrokePoints(
            from: drawing,
            intersecting: canvasRect
        )

        guard !filteredStrokes.isEmpty else {
            return "(no strokes in region)"
        }

        let totalPts = filteredStrokes.reduce(0) { $0 + $1.count }
        print("[AgentRunner] CTC: \(filteredStrokes.count) strokes, \(totalPts) points in region")

        // Direct pipeline (same as demo Predict): normalize → features → predict
        let normalized = normalizeStrokes(filteredStrokes)
        let features = extractPointFeatures(normalized)
        let nPoints = features.count / FEATURE_DIM
        guard nPoints >= 2 else {
            return "(too few points)"
        }

        let result = try model.predict(features: features, seqLen: nPoints)
        return result.raw
    }

    // MARK: - Pure helpers

    /// Convert screen rect → canvas coordinate space
    private func screenRectToCanvasRect(
        _ screenRect: CGRect,
        captureToken: AgentCaptureToken
    ) -> CGRect {
        let imageRect = captureToken.screenRectToImageRect?(screenRect) ?? .zero
        let scale = PageConstants.renderScale
        return CGRect(
            x: imageRect.origin.x * scale,
            y: imageRect.origin.y * scale,
            width: imageRect.width * scale,
            height: imageRect.height * scale
        )
    }

    /// Extract StrokePoints from PKStrokes that intersect a canvas-space rect.
    /// Samples PKStrokePath at integer parametric values (matching raw touch input).
    private func extractStrokePoints(
        from drawing: PKDrawing,
        intersecting canvasRect: CGRect
    ) -> [[StrokePoint]] {
        drawing.strokes.compactMap { stroke -> [StrokePoint]? in
            guard stroke.renderBounds.intersects(canvasRect) else { return nil }
            let path = stroke.path
            guard path.count >= 2 else { return nil }

            let points: [StrokePoint] = (0..<path.count).map { i in
                let loc = path[i].location
                return StrokePoint(x: Float(loc.x), y: Float(loc.y), t: 0)
            }

            return points.count >= 2 ? points : nil
        }
    }
}
