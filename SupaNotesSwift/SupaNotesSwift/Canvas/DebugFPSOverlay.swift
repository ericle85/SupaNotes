import UIKit

#if DEBUG
  final class DebugFPSOverlay {
    private let label = UILabel()
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var frameCount: Int = 0

    func attach() {
      guard
        let window = UIApplication.shared.connectedScenes
          .compactMap({ $0 as? UIWindowScene })
          .flatMap(\.windows)
          .first(where: { $0.isKeyWindow })
      else { return }

      label.font = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .bold)
      label.textColor = .white
      label.backgroundColor = UIColor.black.withAlphaComponent(0.6)
      label.textAlignment = .center
      label.layer.cornerRadius = 6
      label.layer.zPosition = .greatestFiniteMagnitude
      label.clipsToBounds = true
      label.isUserInteractionEnabled = false
      label.text = " -- FPS "
      label.sizeToFit()
      label.frame.size.width += 12
      label.frame.size.height += 4

      let safeTop = window.safeAreaInsets.top
      label.frame.origin = CGPoint(
        x: window.bounds.maxX - label.frame.width - 12,
        y: safeTop + 8
      )

      window.addSubview(label)

      displayLink = CADisplayLink(target: self, selector: #selector(tick))
      displayLink?.add(to: .main, forMode: .common)
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
