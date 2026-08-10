import UIKit

#if DEBUG
  final class DebugFPSOverlay {
    private let label = UILabel()
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var frameCount: Int = 0

    func attach(to parent: UIView) {
      label.font = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .bold)
      label.textColor = .white
      label.backgroundColor = UIColor.black.withAlphaComponent(0.6)
      label.textAlignment = .center
      label.layer.cornerRadius = 6
      label.clipsToBounds = true
      label.text = " -- FPS "
      label.sizeToFit()
      label.frame.size.width += 12
      label.frame.size.height += 4
      parent.addSubview(label)

      displayLink = CADisplayLink(target: self, selector: #selector(tick))
      displayLink?.add(to: .main, forMode: .common)
    }

    func layout(in bounds: CGRect, safeArea: UIEdgeInsets) {
      label.frame.origin = CGPoint(
        x: bounds.maxX - label.frame.width - 12,
        y: safeArea.top + 8
      )
      label.superview?.bringSubviewToFront(label)
    }

    @objc private func tick(_ link: CADisplayLink) {
      guard lastTimestamp > 0 else {
        lastTimestamp = link.timestamp
        return
      }

      frameCount += 1
      let elapsed = link.timestamp - lastTimestamp

      guard elapsed >= 0.5 else { return }

      let fps = Double(frameCount) / elapsed
      let rounded = Int(round(fps))
      label.text = " \(rounded) FPS "
      label.textColor = rounded < 60 ? .red : .green
      label.sizeToFit()
      label.frame.size.width += 12
      label.frame.size.height += 4

      frameCount = 0
      lastTimestamp = link.timestamp
    }

    func detach() {
      displayLink?.invalidate()
      displayLink = nil
      label.removeFromSuperview()
    }
  }
#endif
