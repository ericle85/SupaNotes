import UIKit

extension CanvasView {
    @objc func handleMomentumStop(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, scrollView.isDecelerating else { return }
        scrollView.setContentOffset(scrollView.contentOffset, animated: false)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer) -> Bool
    {
        gestureRecognizer === momentumStopGesture
    }

    func setZoomEnabled(_ enabled: Bool) {
        scrollView.pinchGestureRecognizer?.isEnabled = enabled
        scrollView.panGestureRecognizer.isEnabled = enabled
    }

    func viewForZooming(in _: UIScrollView) -> UIView? {
        pageView
    }

    func scrollViewDidZoom(_: UIScrollView) {
        centerContent()
    }

    func scrollViewDidEndZooming(_: UIScrollView, with _: UIView?, atScale scale: CGFloat) {
        pageView.updateGridScale(zoomScale: scale)
    }
}
