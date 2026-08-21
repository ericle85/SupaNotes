import UIKit

extension CanvasView {
    @objc func shareTapped() {
        let collector = pageView.strokeCollector
        guard !collector.lastPipelineStrokes.isEmpty,
              let folderURL = exportStrokeBundle(
                  strokes: collector.lastPipelineStrokes,
                  pipelineResult: collector.lastPipelineResult
              ) else { return }

        let activity = UIActivityViewController(activityItems: [folderURL], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = shareButton
        activity.popoverPresentationController?.sourceRect = shareButton.bounds
        guard let root = window?.windowScene?.keyWindow?.rootViewController else { return }
        root.present(activity, animated: true)
    }
}
