import UIKit

class PullToAddController {
    private var topIndicator: PullToAddPageIndicator?
    private var bottomIndicator: PullToAddPageIndicator?
    private var hasTriggeredTop = false
    private var hasTriggeredBottom = false
    private let hapticFeedback = UIImpactFeedbackGenerator(style: .medium)

    func setupIndicators(in scrollView: UIScrollView) {
        topIndicator?.removeFromSuperview()
        bottomIndicator?.removeFromSuperview()

        let top = PullToAddPageIndicator(direction: .down)
        let bottom = PullToAddPageIndicator(direction: .up)
        scrollView.addSubview(top)
        scrollView.addSubview(bottom)

        topIndicator = top
        bottomIndicator = bottom
        hasTriggeredTop = false
        hasTriggeredBottom = false
    }

    func updatePositions(in scrollView: UIScrollView) {
        let w = Design.PullToAdd.indicatorWidth
        let h = Design.PullToAdd.indicatorHeight
        let contentH = scrollView.contentSize.height
        let viewH = scrollView.bounds.height
        let topInset = scrollView.adjustedContentInset.top
        let bottomInset = scrollView.adjustedContentInset.bottom
        let centerX = scrollView.bounds.midX - w / 2

        topIndicator?.frame = CGRect(x: centerX, y: -(h + topInset), width: w, height: h)
        bottomIndicator?.frame = CGRect(x: centerX, y: max(contentH, viewH) + bottomInset, width: w, height: h)
    }

    func update(for scrollView: UIScrollView) {
        updatePositions(in: scrollView)

        let offsetY = scrollView.contentOffset.y
        let maxOffsetY = max(0, scrollView.contentSize.height - scrollView.bounds.height)

        if offsetY < 0 && scrollView.isDragging {
            let pull = -offsetY
            topIndicator?.alpha = pull > Design.PullToAdd.showThreshold ? 1 : 0
            topIndicator?.updateProgress(pull)
            hasTriggeredTop = pull >= Design.PullToAdd.triggerThreshold
            bottomIndicator?.alpha = 0
            hasTriggeredBottom = false
        } else if offsetY > maxOffsetY && scrollView.contentSize.height > 0 && scrollView.isDragging {
            let pull = offsetY - maxOffsetY
            bottomIndicator?.alpha = pull > Design.PullToAdd.showThreshold ? 1 : 0
            bottomIndicator?.updateProgress(pull)
            hasTriggeredBottom = pull >= Design.PullToAdd.triggerThreshold
            topIndicator?.alpha = 0
            hasTriggeredTop = false
        } else {
            topIndicator?.alpha = 0
            bottomIndicator?.alpha = 0
            topIndicator?.reset()
            bottomIndicator?.reset()
            hasTriggeredTop = false
            hasTriggeredBottom = false
        }
    }

    func handleEndDragging(addPage: () -> Void, addPageAbove: (() -> Void)?) -> PagedCanvasContainer.ScrollAfterRebuild {
        var scroll: PagedCanvasContainer.ScrollAfterRebuild = .none

        if hasTriggeredTop {
            topIndicator?.setTriggered()
            hapticFeedback.impactOccurred()
            scroll = .scrollToFirst
            addPageAbove?()
            hasTriggeredTop = false
        } else if hasTriggeredBottom {
            bottomIndicator?.setTriggered()
            hapticFeedback.impactOccurred()
            scroll = .scrollToLast
            addPage()
            hasTriggeredBottom = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Design.Debounce.pullReset) { [weak self] in
            self?.resetIndicators()
        }

        return scroll
    }

    func resetIndicators() {
        [topIndicator, bottomIndicator].forEach { $0?.reset() }
        hasTriggeredTop = false
        hasTriggeredBottom = false
    }
}
