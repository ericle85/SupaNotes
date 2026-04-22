import UIKit

/// Animated indicator used by pull-to-add-page at the top and bottom.
final class PullToAddPageIndicator: UIView {
    enum Direction {
        case up
        case down
    }

    enum State {
        case idle
        case pulling
        case readyToTrigger
        case triggered
    }

    private let circleSize: CGFloat = 56
    private let circleStrokeWidth: CGFloat = 3
    private let iconPointSize: CGFloat = 22
    private let iconFrameSize: CGFloat = 28
    private let labelFontSize: CGFloat = 13
    private let edgePadding: CGFloat = 12
    private let circleToTextSpacing: CGFloat = 8
    private let colorChangeProgress: CGFloat = 0.3
    private let readyBounceScale: CGFloat = 1.2
    private let triggeredScale: CGFloat = 1.3
    private let readyBounceDuration: Double = 0.6
    private let readyBounceDamping: CGFloat = 0.3
    private let snapBackDuration: Double = 0.2
    private let triggeredAnimationDuration: Double = 0.3
    private let intrinsicWidth: CGFloat = 120
    private let intrinsicBottomPadding: CGFloat = 40

    let direction: Direction
    private(set) var state: State = .idle

    private let circleBackgroundLayer = CAShapeLayer()
    private let circleProgressLayer = CAShapeLayer()
    private let iconImageView = UIImageView()
    private let textLabel = UILabel()
    private let containerView = UIView()

    private let idleColor = UIColor.systemGray4
    private let activeColor = UIColor.systemBlue

    init(direction: Direction) {
        self.direction = direction
        super.init(frame: .zero)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        alpha = 0
        backgroundColor = .clear

        addSubview(containerView)
        containerView.translatesAutoresizingMaskIntoConstraints = false

        let circlePath = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: circleSize, height: circleSize))

        circleBackgroundLayer.path = circlePath.cgPath
        circleBackgroundLayer.fillColor = UIColor.clear.cgColor
        circleBackgroundLayer.strokeColor = idleColor.cgColor
        circleBackgroundLayer.lineWidth = circleStrokeWidth
        containerView.layer.addSublayer(circleBackgroundLayer)

        circleProgressLayer.path = circlePath.cgPath
        circleProgressLayer.fillColor = UIColor.clear.cgColor
        circleProgressLayer.strokeColor = activeColor.cgColor
        circleProgressLayer.lineWidth = circleStrokeWidth
        circleProgressLayer.strokeEnd = 0
        circleProgressLayer.lineCap = .round
        circleProgressLayer.transform = CATransform3DMakeRotation(-.pi / 2, 0, 0, 1)
        circleProgressLayer.position = CGPoint(x: circleSize / 2, y: circleSize / 2)
        circleProgressLayer.bounds = CGRect(x: 0, y: 0, width: circleSize, height: circleSize)
        containerView.layer.addSublayer(circleProgressLayer)

        let iconConfig = UIImage.SymbolConfiguration(pointSize: iconPointSize, weight: .medium)
        iconImageView.image = UIImage(systemName: "doc.badge.plus", withConfiguration: iconConfig)
        iconImageView.tintColor = idleColor
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(iconImageView)

        textLabel.text = "Pull to Add Page"
        textLabel.font = .systemFont(ofSize: labelFontSize, weight: .medium)
        textLabel.textColor = idleColor
        textLabel.textAlignment = .center
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textLabel)

        let isUp = direction == .up

        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            containerView.widthAnchor.constraint(equalToConstant: circleSize),
            containerView.heightAnchor.constraint(equalToConstant: circleSize),

            iconImageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: iconFrameSize),
            iconImageView.heightAnchor.constraint(equalToConstant: iconFrameSize),

            textLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            textLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
            textLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
        ])

        if isUp {
            NSLayoutConstraint.activate([
                containerView.topAnchor.constraint(equalTo: topAnchor, constant: edgePadding),
                textLabel.topAnchor.constraint(equalTo: containerView.bottomAnchor, constant: circleToTextSpacing),
                textLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -edgePadding),
            ])
        } else {
            NSLayoutConstraint.activate([
                textLabel.topAnchor.constraint(equalTo: topAnchor, constant: edgePadding),
                containerView.topAnchor.constraint(equalTo: textLabel.bottomAnchor, constant: circleToTextSpacing),
                containerView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -edgePadding),
            ])
        }
    }

    /// Update animation based on how far user has pulled.
    func updateProgress(_ pullDistance: CGFloat) {
        let progress = min(1, max(0, pullDistance / Design.PullToAdd.triggerThreshold))

        if pullDistance >= Design.PullToAdd.activationThreshold, state == .idle {
            state = .pulling
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        circleProgressLayer.strokeEnd = progress
        CATransaction.commit()

        let isReady = pullDistance >= Design.PullToAdd.triggerThreshold

        if isReady, state == .pulling {
            setReadyState()
        } else if !isReady, state == .readyToTrigger {
            state = .pulling
            textLabel.text = "Pull to Add Page"
            iconImageView.tintColor = activeColor
            textLabel.textColor = activeColor
            circleBackgroundLayer.fillColor = UIColor.clear.cgColor
            circleBackgroundLayer.strokeColor = idleColor.cgColor

            UIView.animate(withDuration: snapBackDuration) {
                self.containerView.transform = .identity
            }
        } else if state == .pulling || state == .idle {
            let color = progress > colorChangeProgress ? activeColor : idleColor
            iconImageView.tintColor = color
            textLabel.textColor = color
        }
    }

    /// Called when user has pulled far enough and can release to add a page.
    func setReadyState() {
        guard state != .readyToTrigger else { return }
        state = .readyToTrigger

        textLabel.text = "Release to Add Page"
        iconImageView.tintColor = .white
        textLabel.textColor = activeColor

        circleBackgroundLayer.fillColor = activeColor.cgColor
        circleBackgroundLayer.strokeColor = activeColor.cgColor
        circleProgressLayer.strokeColor = activeColor.cgColor

        containerView.transform = CGAffineTransform(scaleX: readyBounceScale, y: readyBounceScale)
        UIView.animate(
            withDuration: readyBounceDuration,
            delay: 0,
            usingSpringWithDamping: readyBounceDamping,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction]
        ) {
            self.containerView.transform = .identity
        }
    }

    /// Called right when we actually add a page.
    func setTriggered() {
        state = .triggered

        UIView.animate(withDuration: triggeredAnimationDuration) {
            self.containerView.transform = CGAffineTransform(scaleX: self.triggeredScale, y: self.triggeredScale)
        } completion: { _ in
            self.reset()
        }
    }

    /// Return indicator to the resting state.
    func reset() {
        state = .idle

        containerView.transform = .identity
        circleProgressLayer.strokeEnd = 0
        circleBackgroundLayer.fillColor = UIColor.clear.cgColor
        circleBackgroundLayer.strokeColor = idleColor.cgColor
        circleProgressLayer.strokeColor = activeColor.cgColor

        iconImageView.tintColor = idleColor
        textLabel.text = "Pull to Add Page"
        textLabel.textColor = idleColor
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: intrinsicWidth, height: circleSize + intrinsicBottomPadding)
    }
}
