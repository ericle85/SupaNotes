import SwiftUI
import PencilKit

struct PagedCanvasContainer: UIViewRepresentable {
    @Binding var pages: [Page]
    var tool: PKTool
    var onUndoManagerReady: (UndoManager?) -> Void
    var onPencilDoubleTap: (() -> Void)?
    var onWritingStateChanged: ((Bool) -> Void)?
    var onCurrentPageChanged: ((Int) -> Void)?
    var addPage: () -> Void
    var addPageAbove: (() -> Void)?

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = UIColor(named: "PaperBackground") ?? UIColor.systemGroupedBackground
        scrollView.showsVerticalScrollIndicator = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 0.5
        scrollView.maximumZoomScale = 3.0

        // Container view for zooming
        let containerView = UIView()
        containerView.tag = 999
        scrollView.addSubview(containerView)

        context.coordinator.scrollView = scrollView
        context.coordinator.containerView = containerView

        // Add pencil interaction once on the scroll view (not per-page)
        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = context.coordinator
        scrollView.addInteraction(pencilInteraction)

        // Build initial pages
        context.coordinator.rebuildPages(pages: pages, tool: tool)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.pages = pages
        coordinator.tool = tool
        coordinator.onPencilDoubleTap = onPencilDoubleTap
        coordinator.onWritingStateChanged = onWritingStateChanged
        coordinator.onCurrentPageChanged = onCurrentPageChanged
        coordinator.addPage = addPage
        coordinator.addPageAbove = addPageAbove

        // Update tool on all canvas views
        for canvasView in coordinator.canvasViews {
            canvasView.tool = tool
        }

        // Rebuild if page count changed or initial layout had zero bounds
        let containerWidth = coordinator.containerView?.frame.width ?? 0
        if coordinator.canvasViews.count != pages.count ||
           (!coordinator.hasCompletedInitialLayout && scrollView.bounds.width > 0 && abs(containerWidth - scrollView.bounds.width) > 1) {
            coordinator.hasCompletedInitialLayout = scrollView.bounds.width > 0
            coordinator.rebuildPages(pages: pages, tool: tool)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            pages: pages,
            tool: tool,
            onUndoManagerReady: onUndoManagerReady,
            onPencilDoubleTap: onPencilDoubleTap,
            onWritingStateChanged: onWritingStateChanged,
            onCurrentPageChanged: onCurrentPageChanged,
            addPage: addPage,
            addPageAbove: addPageAbove
        )
    }

    // MARK: - Coordinator
    class Coordinator: NSObject, UIScrollViewDelegate, PKCanvasViewDelegate, UIPencilInteractionDelegate {
        var pages: [Page]
        var tool: PKTool
        var onUndoManagerReady: (UndoManager?) -> Void
        var onPencilDoubleTap: (() -> Void)?
        var onWritingStateChanged: ((Bool) -> Void)?
        var onCurrentPageChanged: ((Int) -> Void)?
        var addPage: () -> Void
        var addPageAbove: (() -> Void)?

        weak var scrollView: UIScrollView?
        weak var containerView: UIView?
        var canvasViews: [PKCanvasView] = []
        private var isAddingPage = false
        var hasCompletedInitialLayout = false
        private var saveWorkItem: DispatchWorkItem?

        // Pull-to-add indicators
        private var topIndicator: PullToAddPageIndicator?
        private var bottomIndicator: PullToAddPageIndicator?
        private var hasTriggeredTop = false
        private var hasTriggeredBottom = false
        private let hapticFeedback = UIImpactFeedbackGenerator(style: .medium)

        init(
            pages: [Page],
            tool: PKTool,
            onUndoManagerReady: @escaping (UndoManager?) -> Void,
            onPencilDoubleTap: (() -> Void)?,
            onWritingStateChanged: ((Bool) -> Void)?,
            onCurrentPageChanged: ((Int) -> Void)?,
            addPage: @escaping () -> Void,
            addPageAbove: (() -> Void)?
        ) {
            self.pages = pages
            self.tool = tool
            self.onUndoManagerReady = onUndoManagerReady
            self.onPencilDoubleTap = onPencilDoubleTap
            self.onWritingStateChanged = onWritingStateChanged
            self.onCurrentPageChanged = onCurrentPageChanged
            self.addPage = addPage
            self.addPageAbove = addPageAbove
        }

        func rebuildPages(pages: [Page], tool: PKTool) {
            guard let containerView = containerView, let scrollView = scrollView else { return }

            // Remove existing canvas views
            for canvas in canvasViews {
                canvas.removeFromSuperview()
            }
            canvasViews.removeAll()

            let sortedPages = pages.sorted { $0.orderIndex < $1.orderIndex }
            let pageW = PageConstants.pageWidth
            let pageH = PageConstants.pageHeight
            let gap = PageConstants.pageGap

            let totalHeight = CGFloat(sortedPages.count) * pageH + CGFloat(max(0, sortedPages.count - 1)) * gap + gap * 2

            containerView.frame = CGRect(
                x: 0, y: 0,
                width: max(pageW + gap * 2, scrollView.bounds.width),
                height: totalHeight
            )
            scrollView.contentSize = containerView.frame.size

            for (index, page) in sortedPages.enumerated() {
                let canvasView = PKCanvasView()
                canvasView.drawingPolicy = .pencilOnly
                canvasView.backgroundColor = .white
                canvasView.overrideUserInterfaceStyle = .light
                canvasView.isScrollEnabled = false
                canvasView.tool = tool
                canvasView.tag = index

                // Load drawing data
                if !page.drawingData.isEmpty,
                   let drawing = try? PKDrawing(data: page.drawingData) {
                    canvasView.drawing = drawing
                }

                canvasView.delegate = self

                // Add page shadow
                canvasView.layer.shadowColor = UIColor.black.cgColor
                canvasView.layer.shadowOpacity = 0.08
                canvasView.layer.shadowOffset = CGSize(width: 0, height: 2)
                canvasView.layer.shadowRadius = 8

                let xOffset = (containerView.frame.width - pageW) / 2
                let yOffset = gap + CGFloat(index) * (pageH + gap)
                canvasView.frame = CGRect(x: xOffset, y: yOffset, width: pageW, height: pageH)

                containerView.addSubview(canvasView)
                canvasViews.append(canvasView)
            }

            // Reset add-page guard after rebuild
            isAddingPage = false

            // Setup pull indicators
            setupPullIndicators()

            // Report undo manager from first page
            if let firstCanvas = canvasViews.first {
                DispatchQueue.main.async { [weak self] in
                    self?.onUndoManagerReady(firstCanvas.undoManager)
                }
            }
        }

        private func setupPullIndicators() {
            guard let scrollView = scrollView else { return }

            // Remove existing indicators
            topIndicator?.removeFromSuperview()
            bottomIndicator?.removeFromSuperview()

            // Add to scrollView (not containerView) so they DON'T zoom
            let top = PullToAddPageIndicator(direction: .down)
            scrollView.addSubview(top)

            let bottom = PullToAddPageIndicator(direction: .up)
            scrollView.addSubview(bottom)

            topIndicator = top
            bottomIndicator = bottom
            hasTriggeredTop = false
            hasTriggeredBottom = false
        }

        /// Position indicators based on where the containerView actually is (accounts for zoom + centering)
        private func updateIndicatorPositions() {
            guard let scrollView = scrollView, let containerView = containerView else { return }

            let indicatorWidth: CGFloat = 150
            let indicatorHeight: CGFloat = 100
            let indicatorGap: CGFloat = 40

            // Horizontally centered on screen (not on content)
            let centerX = scrollView.bounds.midX - indicatorWidth / 2

            // Vertically positioned relative to actual content edges
            let contentTop = containerView.frame.minY
            let contentBottom = containerView.frame.maxY

            topIndicator?.frame = CGRect(
                x: centerX,
                y: contentTop - indicatorHeight - indicatorGap,
                width: indicatorWidth,
                height: indicatorHeight
            )

            bottomIndicator?.frame = CGRect(
                x: centerX,
                y: contentBottom + indicatorGap,
                width: indicatorWidth,
                height: indicatorHeight
            )
        }

        // MARK: - UIScrollViewDelegate

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            containerView
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            updateCurrentPage()
            updatePullIndicators(scrollView)
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContainerIfNeeded()
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if hasTriggeredTop {
                topIndicator?.setTriggered()
                hapticFeedback.impactOccurred()
                // Remember current content height to adjust scroll after page added above
                let oldContentHeight = scrollView.contentSize.height
                addPageAbove?()
                hasTriggeredTop = false
                // After page is added above, adjust scroll offset to keep view on same content
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    guard let scrollView = self?.scrollView else { return }
                    let newContentHeight = scrollView.contentSize.height
                    let heightDelta = newContentHeight - oldContentHeight
                    if heightDelta > 0 {
                        scrollView.setContentOffset(
                            CGPoint(x: scrollView.contentOffset.x, y: scrollView.contentOffset.y + heightDelta),
                            animated: true
                        )
                    }
                }
            } else if hasTriggeredBottom {
                bottomIndicator?.setTriggered()
                hapticFeedback.impactOccurred()
                addPage()
                hasTriggeredBottom = false
                // Scroll to show the new page at the bottom
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    guard let scrollView = self?.scrollView else { return }
                    let bottomY = scrollView.contentSize.height - scrollView.bounds.height
                    if bottomY > 0 {
                        scrollView.setContentOffset(
                            CGPoint(x: scrollView.contentOffset.x, y: bottomY),
                            animated: true
                        )
                    }
                }
            }

            // Reset indicators after drag ends
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.resetPullIndicators()
            }
        }

        private func updatePullIndicators(_ scrollView: UIScrollView) {
            updateIndicatorPositions()

            let offsetY = scrollView.contentOffset.y
            let contentHeight = scrollView.contentSize.height
            let viewHeight = scrollView.bounds.height

            // Max scrollable offset - 0 when content fits in viewport
            let maxOffsetY = max(0, contentHeight - viewHeight)

            let triggerThreshold: CGFloat = 200

            // Top pull (pulling down at top) - negative offset means bouncing past top
            if offsetY < 0 {
                let pullDistance = -offsetY
                topIndicator?.alpha = 1
                topIndicator?.updateProgress(pullDistance)
                hasTriggeredTop = scrollView.isDragging && pullDistance >= triggerThreshold
                bottomIndicator?.alpha = 0
                hasTriggeredBottom = false
            }
            // Bottom pull (pulling up past max scroll position)
            else if offsetY > maxOffsetY && contentHeight > 0 {
                let pullDistance = offsetY - maxOffsetY
                bottomIndicator?.alpha = 1
                bottomIndicator?.updateProgress(pullDistance)
                hasTriggeredBottom = scrollView.isDragging && pullDistance >= triggerThreshold
                topIndicator?.alpha = 0
                hasTriggeredTop = false
            }
            // In middle - hide both
            else {
                topIndicator?.alpha = 0
                bottomIndicator?.alpha = 0
                topIndicator?.reset()
                bottomIndicator?.reset()
                hasTriggeredTop = false
                hasTriggeredBottom = false
            }
        }

        private func resetPullIndicators() {
            topIndicator?.reset()
            bottomIndicator?.reset()
            hasTriggeredTop = false
            hasTriggeredBottom = false
        }

        private func centerContainerIfNeeded() {
            guard let scrollView = scrollView, let containerView = containerView else { return }
            let boundsSize = scrollView.bounds.size
            let contentsSize = scrollView.contentSize

            let xOffset = max(0, (boundsSize.width - contentsSize.width) / 2)
            let yOffset = max(0, (boundsSize.height - contentsSize.height) / 2)
            containerView.center = CGPoint(
                x: contentsSize.width / 2 + xOffset,
                y: contentsSize.height / 2 + yOffset
            )
        }

        private func updateCurrentPage() {
            guard let scrollView = scrollView else { return }
            let zoomScale = scrollView.zoomScale
            let centerY = (scrollView.contentOffset.y + scrollView.bounds.height / 2) / zoomScale
            let pageH = PageConstants.pageHeight
            let gap = PageConstants.pageGap

            let adjustedY = centerY - gap
            let pageIndex = max(0, Int(adjustedY / (pageH + gap)))
            let clampedIndex = min(pageIndex, max(0, pages.count - 1))
            onCurrentPageChanged?(clampedIndex)
        }

        // MARK: - PKCanvasViewDelegate

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let index = canvasView.tag
            let drawing = canvasView.drawing

            // Throttle saves to avoid dataRepresentation() on every stroke delta
            saveWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                let sortedPages = self.pages.sorted { $0.orderIndex < $1.orderIndex }
                guard index < sortedPages.count else { return }
                sortedPages[index].drawingData = drawing.dataRepresentation()
            }
            saveWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
        }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            onWritingStateChanged?(true)
            onUndoManagerReady(canvasView.undoManager)
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            onWritingStateChanged?(false)
            // Force immediate save when tool use ends
            let index = canvasView.tag
            let sortedPages = pages.sorted { $0.orderIndex < $1.orderIndex }
            guard index < sortedPages.count else { return }
            saveWorkItem?.cancel()
            sortedPages[index].drawingData = canvasView.drawing.dataRepresentation()
        }

        // MARK: - UIPencilInteractionDelegate

        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
            onPencilDoubleTap?()
        }
    }
}
