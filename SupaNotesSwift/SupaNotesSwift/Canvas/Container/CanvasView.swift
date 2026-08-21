import PencilKit
import UIKit

final class CanvasView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    let scrollView = UIScrollView()
    let pageView: PageView
    var momentumStopGesture: UIGestureRecognizer?
    let shareButton = UIButton(type: .system)

    init(theme: GridTheme = .adaptive) {
        pageView = PageView(theme: theme)
        super.init(frame: .zero)
        backgroundColor = .systemGray3

        scrollView.delegate = self
        scrollView.minimumZoomScale = 0.75
        scrollView.maximumZoomScale = 2
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false

        let fingerOnly = [UITouch.TouchType.direct.rawValue as NSNumber]
        scrollView.panGestureRecognizer.allowedTouchTypes = fingerOnly
        scrollView.pinchGestureRecognizer?.allowedTouchTypes = fingerOnly
        let stopMomentum = UILongPressGestureRecognizer(
            target: self, action: #selector(handleMomentumStop(_:))
        )
        stopMomentum.minimumPressDuration = 0
        stopMomentum.cancelsTouchesInView = false
        stopMomentum.delegate = self
        momentumStopGesture = stopMomentum
        addSubview(scrollView)

        scrollView.addGestureRecognizer(stopMomentum)
        scrollView.addSubview(pageView)

        shareButton.setImage(UIImage(systemName: "square.and.arrow.up"), for: .normal)
        shareButton.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
        shareButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(shareButton)

        NSLayoutConstraint.activate([
            shareButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 12),
            shareButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
        ])
        pageView.onDrawingStateChanged = { [weak self] in self?.setZoomEnabled(!$0) }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        scrollView.contentSize = PageView.pageSize
        centerContent()
    }

    func centerContent() {
        let bounds = scrollView.bounds
        let size = pageView.frame.size
        let x = max(0, (bounds.width - size.width) / 2)
        let y = max(0, (bounds.height - size.height) / 2)
        scrollView.contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
    }
}
