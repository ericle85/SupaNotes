import UIKit

// MARK: - Pull To Add Page Indicator

/// Animated indicator used by pull-to-add-page at the top and bottom.
final class PullToAddPageIndicator: UIView {
    // Which direction the indicator points.
    enum Direction {
        case up
        case down
    }

    /// Current animation state of the indicator.
    enum State {
        case idle // Not visible, waiting for interaction.
        case pulling // User is pulling but hasn't reached trigger threshold.
        case readyToTrigger // User has pulled far enough to trigger on release.
        case triggered  // Page was just added, playing success animation.
    }

    // MARK: - Design Constants

    private let circleSize: CGFloat = 56 // Size of the circular progress indicator.
    private let circleStrokeWidth: CGFloat = 3 // Thickness of the circle stroke.
    private let iconPointSize: CGFloat = 22 // Point size for the SF Symbol icon.
    private let iconFrameSize: CGFloat = 28 // Frame size for the icon view.
    private let labelFontSize: CGFloat = 13 // Font size for the label text.
    private let edgePadding: CGFloat = 12 // Padding from edges of the view.
    private let circleToTextSpacing: CGFloat = 8 // Spacing between circle and text label.
    private let colorChangeProgress: CGFloat = 0.3 // Progress at which color changes from gray to blue.
    private let readyBounceScale: CGFloat = 1.2
    private let triggeredScale: CGFloat = 1.3 // Scale factor when triggered.
    private let readyBounceDuration: Double = 0.6
    private let readyBounceDamping: CGFloat = 0.3 // Damping ratio for the bounce spring.
    private let snapBackDuration: Double = 0.2
    private let triggeredAnimationDuration: Double = 0.3 // Duration of the triggered animation.
    private let intrinsicWidth: CGFloat = 120 // Preferred width of the indicator.
    private let intrinsicBottomPadding: CGFloat = 40 // Extra padding at the bottom for intrinsic size.

    // MARK: - Properties

    let direction: Direction // Which direction this indicator points.
    private(set) var state: State = .idle // Current animation state.

    // MARK: - UI Components

    private let circleBackgroundLayer = CAShapeLayer() // Background circle layer (always visible gray ring).
    private let circleProgressLayer = CAShapeLayer() // Progress circle layer (fills as user pulls).
    private let iconImageView = UIImageView() // Icon image view showing the plus symbol.
    private let textLabel = UILabel() // Text label showing status message.
    private let containerView = UIView() // Container view for the circle and icon.

    // MARK: - Colors

    
    private let idleColor = UIColor.systemGray4 // Color when idle or not activated.
    private let activeColor = UIColor.systemBlue // Color when activated or ready to trigger.

    // Create a new indicator with the given direction.
    init(direction: Direction) {
        self.direction = direction
        super.init(frame: .zero)
        // Build the UI hierarchy.
        setupUI()
    }

    // This way of creating the view is not used in this app.
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        alpha = 0 // Start hidden.
        backgroundColor = .clear

        // Add container view.
        addSubview(containerView)
        containerView.translatesAutoresizingMaskIntoConstraints = false

        // Create circular path for the progress rings.
        let circlePath = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: circleSize, height: circleSize))

        // Set up background circle (gray ring).
        circleBackgroundLayer.path = circlePath.cgPath
        circleBackgroundLayer.fillColor = UIColor.clear.cgColor
        circleBackgroundLayer.strokeColor = idleColor.cgColor
        circleBackgroundLayer.lineWidth = circleStrokeWidth
        containerView.layer.addSublayer(circleBackgroundLayer)

        // Set up progress circle (blue ring that fills).
        circleProgressLayer.path = circlePath.cgPath
        circleProgressLayer.fillColor = UIColor.clear.cgColor
        circleProgressLayer.strokeColor = activeColor.cgColor
        circleProgressLayer.lineWidth = circleStrokeWidth
        circleProgressLayer.strokeEnd = 0
        circleProgressLayer.lineCap = .round
        // Rotate so progress starts from the top.
        circleProgressLayer.transform = CATransform3DMakeRotation(-.pi / 2, 0, 0, 1)
        circleProgressLayer.position = CGPoint(x: circleSize / 2, y: circleSize / 2)
        circleProgressLayer.bounds = CGRect(x: 0, y: 0, width: circleSize, height: circleSize)
        containerView.layer.addSublayer(circleProgressLayer)

        // Set up icon (plus symbol).
        let iconConfig = UIImage.SymbolConfiguration(pointSize: iconPointSize, weight: .medium)
        iconImageView.image = UIImage(systemName: "doc.badge.plus", withConfiguration: iconConfig)
        iconImageView.tintColor = idleColor
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(iconImageView)

        // Set up text label.
        textLabel.text = "Pull to Add Page"
        textLabel.font = .systemFont(ofSize: labelFontSize, weight: .medium)
        textLabel.textColor = idleColor
        textLabel.textAlignment = .center
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textLabel)

        // Layout depends on direction (up = circle above text, down = text above circle).
        let isUp = direction == .up

        NSLayoutConstraint.activate([
            // Center container horizontally.
            containerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            containerView.widthAnchor.constraint(equalToConstant: circleSize),
            containerView.heightAnchor.constraint(equalToConstant: circleSize),

            // Center icon in container.
            iconImageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: iconFrameSize),
            iconImageView.heightAnchor.constraint(equalToConstant: iconFrameSize),

            // Center text horizontally with minimum margins.
            textLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            textLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
            textLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
        ])

        if isUp {
            // Circle above text for up direction.
            NSLayoutConstraint.activate([
                containerView.topAnchor.constraint(equalTo: topAnchor, constant: edgePadding),
                textLabel.topAnchor.constraint(equalTo: containerView.bottomAnchor, constant: circleToTextSpacing),
                textLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -edgePadding),
            ])
        } else {
            // Text above circle for down direction.
            NSLayoutConstraint.activate([
                textLabel.topAnchor.constraint(equalTo: topAnchor, constant: edgePadding),
                containerView.topAnchor.constraint(equalTo: textLabel.bottomAnchor, constant: circleToTextSpacing),
                containerView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -edgePadding),
            ])
        }
    }

    /// Update animation based on how far user has pulled.
    func updateProgress(_ pullDistance: CGFloat) {
        // Normalize pull distance to 0-1 range.
        let progress = min(1, max(0, pullDistance / Design.PullToAdd.triggerThreshold))

        // Transition from idle to pulling state when pull starts.
        if pullDistance >= Design.PullToAdd.activationThreshold, state == .idle {
            state = .pulling
        }

        // Update progress ring without animation (immediate feedback).
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        circleProgressLayer.strokeEnd = progress
        CATransaction.commit()

        // Check if we've reached the trigger threshold.
        let isReady = pullDistance >= Design.PullToAdd.triggerThreshold

        // Transition to ready state when threshold is reached.
        if isReady, state == .pulling {
            setReadyState()
        // Snap back to pulling if user pulls back below threshold.
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
        // Update colors based on progress while pulling.
        } else if state == .pulling || state == .idle {
            let color = progress > colorChangeProgress ? activeColor : idleColor
            iconImageView.tintColor = color
            textLabel.textColor = color
        }
    }

    /// Called when user has pulled far enough and can release to add a page.
    func setReadyState() {
        // Only animate if we're not already in ready state.
        guard state != .readyToTrigger else { return }
        state = .readyToTrigger

        // Update text to indicate ready state.
        textLabel.text = "Release to Add Page"
        iconImageView.tintColor = .white
        textLabel.textColor = activeColor

        // Fill the circle with active color.
        circleBackgroundLayer.fillColor = activeColor.cgColor
        circleBackgroundLayer.strokeColor = activeColor.cgColor
        circleProgressLayer.strokeColor = activeColor.cgColor

        // Play bounce animation to indicate ready state.
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

        // Play scale-up animation then reset.
        UIView.animate(withDuration: triggeredAnimationDuration) {
            self.containerView.transform = CGAffineTransform(scaleX: self.triggeredScale, y: self.triggeredScale)
        } completion: { _ in
            self.reset()
        }
    }

    /// Return indicator to the resting state.
    func reset() {
        state = .idle

        // Reset all visual properties to initial state.
        containerView.transform = .identity
        circleProgressLayer.strokeEnd = 0
        circleBackgroundLayer.fillColor = UIColor.clear.cgColor
        circleBackgroundLayer.strokeColor = idleColor.cgColor
        circleProgressLayer.strokeColor = activeColor.cgColor

        iconImageView.tintColor = idleColor
        textLabel.text = "Pull to Add Page"
        textLabel.textColor = idleColor
    }

    /// Return the preferred size for this view.
    override var intrinsicContentSize: CGSize {
        CGSize(width: intrinsicWidth, height: circleSize + intrinsicBottomPadding)
    }
}
