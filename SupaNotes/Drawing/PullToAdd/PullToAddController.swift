import UIKit

// MARK: - Pull To Add Controller

/// Controls the pull-to-add-page behavior at the top and bottom of the scroll view.
final class PullToAddController {
    /// Indicator shown when pulling down at the top.
    private var topIndicator: PullToAddPageIndicator?
    /// Indicator shown when pulling up at the bottom.
    private var bottomIndicator: PullToAddPageIndicator?
    /// Whether the top pull threshold has been reached.
    private var hasTriggeredTop = false
    /// Whether the bottom pull threshold has been reached.
    private var hasTriggeredBottom = false
    /// Haptic feedback when page is added.
    private let hapticFeedback = UIImpactFeedbackGenerator(style: .medium)

    /// Create and position the pull-to-add indicators.
    func setupIndicators(in scrollView: UIScrollView) {
        // Remove old indicators if they exist.
        topIndicator?.removeFromSuperview()
        bottomIndicator?.removeFromSuperview()

        // Create new indicators for top and bottom.
        let top = PullToAddPageIndicator(direction: .down)
        let bottom = PullToAddPageIndicator(direction: .up)
        scrollView.addSubview(top)
        scrollView.addSubview(bottom)

        // Save references and reset trigger state.
        topIndicator = top
        bottomIndicator = bottom
        hasTriggeredTop = false
        hasTriggeredBottom = false
    }

    /// Update indicator positions based on scroll view layout.
    func updatePositions(in scrollView: UIScrollView) {
        // Read design constants.
        let width = Design.PullToAdd.indicatorWidth
        let height = Design.PullToAdd.indicatorHeight
        // Get scroll view dimensions.
        let contentHeight = scrollView.contentSize.height
        let viewHeight = scrollView.bounds.height
        let topInset = scrollView.adjustedContentInset.top
        let bottomInset = scrollView.adjustedContentInset.bottom
        // Center horizontally.
        let centerX = scrollView.bounds.midX - width / 2

        // Position top indicator above the content (visible when pulling down).
        topIndicator?.frame = CGRect(x: centerX, y: -(height + topInset), width: width, height: height)
        // Position bottom indicator below the content (visible when pulling up).
        bottomIndicator?.frame = CGRect(x: centerX, y: max(contentHeight, viewHeight) + bottomInset, width: width, height: height)
    }

    /// Update indicator visibility and progress based on scroll position.
    func update(for scrollView: UIScrollView) {
        // First ensure indicators are in the right positions.
        updatePositions(in: scrollView)

        // Calculate how far we've scrolled.
        let offsetY = scrollView.contentOffset.y
        let maxOffsetY = max(0, scrollView.contentSize.height - scrollView.bounds.height)

        // Handle pulling down at the top.
        if offsetY < 0, scrollView.isDragging {
            let pull = -offsetY
            // Show indicator when pulled past threshold.
            topIndicator?.alpha = pull > Design.PullToAdd.showThreshold ? 1 : 0
            topIndicator?.updateProgress(pull)
            // Mark as triggered when pull distance is sufficient.
            hasTriggeredTop = pull >= Design.PullToAdd.triggerThreshold
            // Hide bottom indicator.
            bottomIndicator?.alpha = 0
            hasTriggeredBottom = false
        // Handle pulling up at the bottom.
        } else if offsetY > maxOffsetY, scrollView.contentSize.height > 0, scrollView.isDragging {
            let pull = offsetY - maxOffsetY
            // Show indicator when pulled past threshold.
            bottomIndicator?.alpha = pull > Design.PullToAdd.showThreshold ? 1 : 0
            bottomIndicator?.updateProgress(pull)
            // Mark as triggered when pull distance is sufficient.
            hasTriggeredBottom = pull >= Design.PullToAdd.triggerThreshold
            // Hide top indicator.
            topIndicator?.alpha = 0
            hasTriggeredTop = false
        // Hide both indicators when not pulling.
        } else {
            topIndicator?.alpha = 0
            bottomIndicator?.alpha = 0
            topIndicator?.reset()
            bottomIndicator?.reset()
            hasTriggeredTop = false
            hasTriggeredBottom = false
        }
    }

    /// Handle the end of a drag gesture - trigger page add if threshold was reached.
    func handleEndDragging(addPage: () -> Void, addPageAbove: (() -> Void)?) -> PagedCanvasContainer.ScrollAfterRebuild {
        var scroll: PagedCanvasContainer.ScrollAfterRebuild = .none

        // If top trigger was reached, add a page above.
        if hasTriggeredTop {
            topIndicator?.setTriggered()
            hapticFeedback.impactOccurred()
            scroll = .scrollToFirst
            addPageAbove?()
            hasTriggeredTop = false
        // If bottom trigger was reached, add a page below.
        } else if hasTriggeredBottom {
            bottomIndicator?.setTriggered()
            hapticFeedback.impactOccurred()
            scroll = .scrollToLast
            addPage()
            hasTriggeredBottom = false
        }

        // Reset indicators after a short delay.
        DispatchQueue.main.asyncAfter(deadline: .now() + Design.Debounce.pullReset) { [weak self] in
            self?.resetIndicators()
        }

        return scroll
    }

    /// Reset both indicators to their idle state.
    func resetIndicators() {
        // Reset each indicator's visual state.
        [topIndicator, bottomIndicator].forEach { $0?.reset() }
        // Reset trigger flags.
        hasTriggeredTop = false
        hasTriggeredBottom = false
    }
}
