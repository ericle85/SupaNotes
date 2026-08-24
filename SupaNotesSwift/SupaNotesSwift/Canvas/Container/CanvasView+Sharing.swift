import PencilKit
import UIKit

extension CanvasView {
    @objc func shareTapped() {
        let strokes = pageView.canvasView.drawing.strokes
        guard !strokes.isEmpty,
              let folderURL = exportStrokeBundle(strokes: strokes) else { return }

        let activity = UIActivityViewController(activityItems: [folderURL], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = shareButton
        activity.popoverPresentationController?.sourceRect = shareButton.bounds
        guard let root = window?.windowScene?.keyWindow?.rootViewController else { return }
        root.present(activity, animated: true)
    }
}
