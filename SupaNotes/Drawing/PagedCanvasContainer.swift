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

        let containerView = UIView()
        containerView.tag = 999
        scrollView.addSubview(containerView)

        context.coordinator.scrollView = scrollView
        context.coordinator.containerView = containerView

        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = context.coordinator
        scrollView.addInteraction(pencilInteraction)

        context.coordinator.rebuildPages(pages: pages, tool: tool)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        let c = context.coordinator
        c.pages = pages
        c.tool = tool
        c.onPencilDoubleTap = onPencilDoubleTap
        c.onWritingStateChanged = onWritingStateChanged
        c.onCurrentPageChanged = onCurrentPageChanged
        c.addPage = addPage
        c.addPageAbove = addPageAbove

        c.canvasViews.forEach { $0.tool = tool }

        let containerWidth = c.containerView?.frame.width ?? 0
        let needsRebuild = c.canvasViews.count != pages.count
            || (!c.hasCompletedInitialLayout && scrollView.bounds.width > 0 && abs(containerWidth - scrollView.bounds.width) > 1)

        if needsRebuild {
            c.hasCompletedInitialLayout = scrollView.bounds.width > 0
            c.rebuildPages(pages: pages, tool: tool)
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

    // MARK: - Scroll Action
    enum ScrollAfterRebuild {
        case none
        case scrollToFirst   // New page added above
        case scrollToLast    // New page added below
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
        var hasCompletedInitialLayout = false
        private var saveWorkItem: DispatchWorkItem?

        // Pull-to-add state
        private var topIndicator: PullToAddPageIndicator?
        private var bottomIndicator: PullToAddPageIndicator?
        private var hasTriggeredTop = false
        private var hasTriggeredBottom = false
        private let hapticFeedback = UIImpactFeedbackGenerator(style: .medium)

        // Pending scroll action after rebuild
        var pendingScroll: ScrollAfterRebuild = .none

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

        // MARK: - Page Layout

        func rebuildPages(pages: [Page], tool: PKTool) {
            guard let containerView = containerView, let scrollView = scrollView else { return }

            // Reset zoom BEFORE setting frames to avoid transform conflicts
            if pendingScroll != .none {
                scrollView.zoomScale = 1.0
            }

            canvasViews.forEach { $0.removeFromSuperview() }
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
                let canvasView = makeCanvasView(for: page, at: index, tool: tool, pageW: pageW, pageH: pageH, gap: gap, containerWidth: containerView.frame.width)
                containerView.addSubview(canvasView)
                canvasViews.append(canvasView)
            }

            centerContainerIfNeeded()
            setupPullIndicators()
            applyPendingScroll(pageH: pageH, gap: gap, pageCount: sortedPages.count)

            if let firstCanvas = canvasViews.first {
                DispatchQueue.main.async { [weak self] in
                    self?.onUndoManagerReady(firstCanvas.undoManager)
                }
            }
        }

        private func makeCanvasView(for page: Page, at index: Int, tool: PKTool, pageW: CGFloat, pageH: CGFloat, gap: CGFloat, containerWidth: CGFloat) -> PKCanvasView {
            let canvasView = PKCanvasView()
            canvasView.drawingPolicy = .pencilOnly
            canvasView.backgroundColor = .white
            canvasView.overrideUserInterfaceStyle = .light
            canvasView.isScrollEnabled = false
            canvasView.tool = tool
            canvasView.tag = index
            canvasView.delegate = self

            if !page.drawingData.isEmpty, let drawing = try? PKDrawing(data: page.drawingData) {
                canvasView.drawing = drawing
            }

            canvasView.layer.shadowColor = UIColor.black.cgColor
            canvasView.layer.shadowOpacity = 0.08
            canvasView.layer.shadowOffset = CGSize(width: 0, height: 2)
            canvasView.layer.shadowRadius = 8

            let xOffset = (containerWidth - pageW) / 2
            let yOffset = gap + CGFloat(index) * (pageH + gap)
            canvasView.frame = CGRect(x: xOffset, y: yOffset, width: pageW, height: pageH)
            return canvasView
        }

        /// After rebuild, scroll to the newly added page (zoom already reset in rebuildPages)
        private func applyPendingScroll(pageH: CGFloat, gap: CGFloat, pageCount: Int) {
            guard let scrollView = scrollView else { return }
            let action = pendingScroll
            pendingScroll = .none

            switch action {
            case .none:
                return
            case .scrollToFirst:
                scrollView.setContentOffset(.zero, animated: false)
            case .scrollToLast:
                let lastPageY = gap + CGFloat(pageCount - 1) * (pageH + gap)
                let targetY = max(0, lastPageY - 20)
                let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
                scrollView.setContentOffset(CGPoint(x: 0, y: min(targetY, maxY)), animated: false)
            }
        }

        // MARK: - Pull Indicators

        private func setupPullIndicators() {
            guard let scrollView = scrollView else { return }

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

        private func updateIndicatorPositions() {
            guard let scrollView = scrollView else { return }

            let w: CGFloat = 150
            let h: CGFloat = 100
            let contentH = scrollView.contentSize.height
            let viewH = scrollView.bounds.height
            let topInset = scrollView.adjustedContentInset.top
            let bottomInset = scrollView.adjustedContentInset.bottom
            let centerX = scrollView.bounds.midX - w / 2

            topIndicator?.frame = CGRect(x: centerX, y: -(h + topInset), width: w, height: h)
            bottomIndicator?.frame = CGRect(x: centerX, y: max(contentH, viewH) + bottomInset, width: w, height: h)
        }

        private func updatePullIndicators(_ scrollView: UIScrollView) {
            updateIndicatorPositions()

            let offsetY = scrollView.contentOffset.y
            let maxOffsetY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
            let triggerThreshold: CGFloat = 200
            let showThreshold: CGFloat = 10

            if offsetY < 0 && scrollView.isDragging {
                let pull = -offsetY
                topIndicator?.alpha = pull > showThreshold ? 1 : 0
                topIndicator?.updateProgress(pull)
                hasTriggeredTop = pull >= triggerThreshold
                bottomIndicator?.alpha = 0
                hasTriggeredBottom = false
            } else if offsetY > maxOffsetY && scrollView.contentSize.height > 0 && scrollView.isDragging {
                let pull = offsetY - maxOffsetY
                bottomIndicator?.alpha = pull > showThreshold ? 1 : 0
                bottomIndicator?.updateProgress(pull)
                hasTriggeredBottom = pull >= triggerThreshold
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

        private func resetPullIndicators() {
            [topIndicator, bottomIndicator].forEach { $0?.reset() }
            hasTriggeredTop = false
            hasTriggeredBottom = false
        }

        // MARK: - UIScrollViewDelegate

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { containerView }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            updateCurrentPage()
            updatePullIndicators(scrollView)
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) { centerContainerIfNeeded() }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if hasTriggeredTop {
                topIndicator?.setTriggered()
                hapticFeedback.impactOccurred()
                pendingScroll = .scrollToFirst
                addPageAbove?()
                hasTriggeredTop = false
            } else if hasTriggeredBottom {
                bottomIndicator?.setTriggered()
                hapticFeedback.impactOccurred()
                pendingScroll = .scrollToLast
                addPage()
                hasTriggeredBottom = false
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.resetPullIndicators()
            }
        }

        // MARK: - Helpers

        private func centerContainerIfNeeded() {
            guard let scrollView = scrollView, let containerView = containerView else { return }
            let bounds = scrollView.bounds.size
            let content = scrollView.contentSize

            containerView.center = CGPoint(
                x: content.width / 2 + max(0, (bounds.width - content.width) / 2),
                y: content.height / 2 + max(0, (bounds.height - content.height) / 2)
            )
        }

        private func updateCurrentPage() {
            guard let scrollView = scrollView else { return }
            let centerY = (scrollView.contentOffset.y + scrollView.bounds.height / 2) / scrollView.zoomScale
            let pageH = PageConstants.pageHeight
            let gap = PageConstants.pageGap
            let pageIndex = max(0, Int((centerY - gap) / (pageH + gap)))
            onCurrentPageChanged?(min(pageIndex, max(0, pages.count - 1)))
        }

        // MARK: - PKCanvasViewDelegate

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let index = canvasView.tag
            let drawing = canvasView.drawing

            saveWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let sorted = self.pages.sorted { $0.orderIndex < $1.orderIndex }
                guard index < sorted.count else { return }
                sorted[index].drawingData = drawing.dataRepresentation()
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
            let index = canvasView.tag
            let sorted = pages.sorted { $0.orderIndex < $1.orderIndex }
            guard index < sorted.count else { return }
            saveWorkItem?.cancel()
            sorted[index].drawingData = canvasView.drawing.dataRepresentation()
        }

        // MARK: - UIPencilInteractionDelegate

        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
            onPencilDoubleTap?()
        }
    }
}
