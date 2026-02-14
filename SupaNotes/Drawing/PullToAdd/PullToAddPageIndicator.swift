import UIKit

class PullToAddPageIndicator: UIView {

    enum Direction {
        case up    // Indicator at bottom, pull up to add page below
        case down  // Indicator at top, pull down to add page above
    }

    enum State {
        case idle
        case pulling
        case readyToTrigger
        case triggered
    }

    // MARK: - Constants
    private let circleSize: CGFloat = 56
    private let activationThreshold: CGFloat = 80
    private let triggerThreshold: CGFloat = 200

    // MARK: - Properties
    let direction: Direction
    private(set) var state: State = .idle

    // MARK: - UI Components
    private let circleBackgroundLayer = CAShapeLayer()
    private let circleProgressLayer = CAShapeLayer()
    private let iconImageView = UIImageView()
    private let textLabel = UILabel()
    private let containerView = UIView()

    // MARK: - Colors
    private let idleColor = UIColor.systemGray4
    private let activeColor = UIColor.systemBlue

    // MARK: - Init
    init(direction: Direction) {
        self.direction = direction
        super.init(frame: .zero)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup
    private func setupUI() {
        // Start hidden - visibility controlled by scroll view
        alpha = 0
        backgroundColor = .clear

        addSubview(containerView)
        containerView.translatesAutoresizingMaskIntoConstraints = false

        // Circle background (gray stroke)
        let circlePath = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: circleSize, height: circleSize))

        circleBackgroundLayer.path = circlePath.cgPath
        circleBackgroundLayer.fillColor = UIColor.clear.cgColor
        circleBackgroundLayer.strokeColor = idleColor.cgColor
        circleBackgroundLayer.lineWidth = 3
        containerView.layer.addSublayer(circleBackgroundLayer)

        // Circle progress (blue stroke that fills)
        circleProgressLayer.path = circlePath.cgPath
        circleProgressLayer.fillColor = UIColor.clear.cgColor
        circleProgressLayer.strokeColor = activeColor.cgColor
        circleProgressLayer.lineWidth = 3
        circleProgressLayer.strokeEnd = 0
        circleProgressLayer.lineCap = .round
        // Start from top (rotate -90 degrees)
        circleProgressLayer.transform = CATransform3DMakeRotation(-.pi / 2, 0, 0, 1)
        circleProgressLayer.position = CGPoint(x: circleSize / 2, y: circleSize / 2)
        circleProgressLayer.bounds = CGRect(x: 0, y: 0, width: circleSize, height: circleSize)
        containerView.layer.addSublayer(circleProgressLayer)

        // Icon
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        iconImageView.image = UIImage(systemName: "doc.badge.plus", withConfiguration: config)
        iconImageView.tintColor = idleColor
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(iconImageView)

        // Text label
        textLabel.text = "Pull to Add Page"
        textLabel.font = .systemFont(ofSize: 13, weight: .medium)
        textLabel.textColor = idleColor
        textLabel.textAlignment = .center
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textLabel)

        // Layout
        let isUp = direction == .up

        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            containerView.widthAnchor.constraint(equalToConstant: circleSize),
            containerView.heightAnchor.constraint(equalToConstant: circleSize),

            iconImageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 28),
            iconImageView.heightAnchor.constraint(equalToConstant: 28),

            textLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            textLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
            textLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8)
        ])

        if isUp {
            // Bottom indicator: circle above text
            NSLayoutConstraint.activate([
                containerView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
                textLabel.topAnchor.constraint(equalTo: containerView.bottomAnchor, constant: 8),
                textLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
            ])
        } else {
            // Top indicator: text above circle
            NSLayoutConstraint.activate([
                textLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
                containerView.topAnchor.constraint(equalTo: textLabel.bottomAnchor, constant: 8),
                containerView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
            ])
        }
    }

    // MARK: - Public Methods

    /// Update the indicator based on pull distance (0 to triggerThreshold+)
    func updateProgress(_ pullDistance: CGFloat) {
        let progress = min(1.0, max(0, pullDistance / triggerThreshold))

        // Update state based on activation threshold
        if pullDistance >= activationThreshold && state == .idle {
            state = .pulling
        }

        // Update progress circle
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        circleProgressLayer.strokeEnd = progress
        CATransaction.commit()

        // Update colors based on progress
        let isReady = pullDistance >= triggerThreshold

        if isReady && state == .pulling {
            setReadyState()
        } else if !isReady && state == .readyToTrigger {
            // Went back below threshold
            state = .pulling
            textLabel.text = "Pull to Add Page"
            iconImageView.tintColor = activeColor
            textLabel.textColor = activeColor
            circleBackgroundLayer.fillColor = UIColor.clear.cgColor
            circleBackgroundLayer.strokeColor = idleColor.cgColor

            // Reset scale
            UIView.animate(withDuration: 0.2) {
                self.containerView.transform = .identity
            }
        } else if state == .pulling || state == .idle {
            // Interpolate colors based on progress
            let color = progress > 0.3 ? activeColor : idleColor
            iconImageView.tintColor = color
            textLabel.textColor = color
        }
    }

    /// Transition to ready-to-trigger state with spring animation
    func setReadyState() {
        guard state != .readyToTrigger else { return }
        state = .readyToTrigger

        textLabel.text = "Release to Add Page"
        iconImageView.tintColor = .white
        textLabel.textColor = activeColor

        // Fill the circle background
        circleBackgroundLayer.fillColor = activeColor.cgColor
        circleBackgroundLayer.strokeColor = activeColor.cgColor
        circleProgressLayer.strokeColor = activeColor.cgColor

        // Instantly scale up, then single bouncy spring back to normal
        containerView.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
        UIView.animate(
            withDuration: 0.6,
            delay: 0,
            usingSpringWithDamping: 0.3,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction]
        ) {
            self.containerView.transform = .identity
        }
    }

    /// Called when the action is triggered
    func setTriggered() {
        state = .triggered

        UIView.animate(withDuration: 0.3) {
            self.containerView.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
        } completion: { _ in
            self.reset()
        }
    }

    /// Reset to idle state
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

    // MARK: - Intrinsic Size
    override var intrinsicContentSize: CGSize {
        CGSize(width: 120, height: circleSize + 40)
    }
}
