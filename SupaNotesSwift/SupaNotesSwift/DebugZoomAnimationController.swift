import UIKit

final class DebugZoomAnimationController {
    private var displayLink: CADisplayLink?
    private var zoomPhase: Double = 0
    private var zoomSpeed: Double = 0.5
    private weak var scrollView: UIScrollView?

    let toggleButton = UIButton(type: .system)
    let speedSlider = UISlider()

    init(scrollView: UIScrollView) {
        self.scrollView = scrollView

        toggleButton.setTitle("Zoom Loop", for: .normal)
        toggleButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.8)
        toggleButton.setTitleColor(.white, for: .normal)
        toggleButton.layer.cornerRadius = 8
        toggleButton.addTarget(self, action: #selector(toggleZoomLoop), for: .touchUpInside)

        speedSlider.minimumValue = 0.1
        speedSlider.maximumValue = 3.0
        speedSlider.value = 0.5
        speedSlider.addTarget(self, action: #selector(speedChanged), for: .valueChanged)
        speedSlider.isHidden = true
    }

    @objc private func toggleZoomLoop() {
        if displayLink != nil {
            stopZoomLoop()
        } else {
            startZoomLoop()
        }
    }

    private func startZoomLoop() {
        zoomPhase = 0
        speedSlider.isHidden = false
        toggleButton.setTitle("Stop", for: .normal)
        toggleButton.backgroundColor = UIColor.systemRed.withAlphaComponent(0.8)

        let link = CADisplayLink(target: self, selector: #selector(zoomTick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopZoomLoop() {
        displayLink?.invalidate()
        displayLink = nil
        speedSlider.isHidden = true
        toggleButton.setTitle("Zoom Loop", for: .normal)
        toggleButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.8)
    }

    @objc private func speedChanged() {
        zoomSpeed = Double(speedSlider.value)
    }

    @objc private func zoomTick() {
        guard let link = displayLink, let scrollView = scrollView else { return }
        zoomPhase += link.duration * zoomSpeed

        let normalized = (sin(zoomPhase) + 1) / 2
        let minScale = scrollView.minimumZoomScale
        let maxScale = scrollView.maximumZoomScale
        let scale = minScale + (maxScale - minScale) * normalized
        scrollView.zoomScale = scale
    }
}
