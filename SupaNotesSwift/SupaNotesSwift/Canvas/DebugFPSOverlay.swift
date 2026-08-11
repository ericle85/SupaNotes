import UIKit

#if DEBUG
  final class DebugFPSOverlay {
    private let label = UILabel()
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0

    private static var drawCount: Int = 0
    private static let lock = NSLock()

    static func recordDraw() {
      lock.lock()
      drawCount += 1
      lock.unlock()
    }

    private static func consumeDrawCount() -> Int {
      lock.lock()
      let count = drawCount
      drawCount = 0
      lock.unlock()
      return count
    }

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

      let elapsed = link.timestamp - lastTimestamp
      guard elapsed >= 0.5 else { return }

      let count = Self.consumeDrawCount()
      let fps = Double(count) / elapsed
      let rounded = Int(round(fps))
      label.text = " \(rounded) FPS "
      label.textColor = rounded < 60 ? .red : .green
      label.sizeToFit()
      label.frame.size.width += 12
      label.frame.size.height += 4

      lastTimestamp = link.timestamp
    }

    func detach() {
      displayLink?.invalidate()
      displayLink = nil
      label.removeFromSuperview()
    }
  }
#endif
