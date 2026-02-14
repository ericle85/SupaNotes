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

        // Update tool on all canvas views
        for canvasView in coordinator.canvasViews {
            canvasView.tool = tool
        }

        // Rebuild if page count changed
        if coordinator.canvasViews.count != pages.count {
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
            addPage: addPage
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

        weak var scrollView: UIScrollView?
        weak var containerView: UIView?
        var canvasViews: [PKCanvasView] = []
        private var isAddingPage = false
        private var saveWorkItem: DispatchWorkItem?

        init(
            pages: [Page],
            tool: PKTool,
            onUndoManagerReady: @escaping (UndoManager?) -> Void,
            onPencilDoubleTap: (() -> Void)?,
            onWritingStateChanged: ((Bool) -> Void)?,
            onCurrentPageChanged: ((Int) -> Void)?,
            addPage: @escaping () -> Void
        ) {
            self.pages = pages
            self.tool = tool
            self.onUndoManagerReady = onUndoManagerReady
            self.onPencilDoubleTap = onPencilDoubleTap
            self.onWritingStateChanged = onWritingStateChanged
            self.onCurrentPageChanged = onCurrentPageChanged
            self.addPage = addPage
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

                // Add pencil interaction
                let pencilInteraction = UIPencilInteraction()
                pencilInteraction.delegate = self
                canvasView.addInteraction(pencilInteraction)

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

            // Report undo manager from first page
            if let firstCanvas = canvasViews.first {
                DispatchQueue.main.async { [weak self] in
                    self?.onUndoManagerReady(firstCanvas.undoManager)
                }
            }
        }

        // MARK: - UIScrollViewDelegate

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            containerView
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            updateCurrentPage()
            checkForNewPageNeeded(scrollView)
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContainerIfNeeded()
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

        private func checkForNewPageNeeded(_ scrollView: UIScrollView) {
            // Guard: don't add multiple pages at once, and don't add during zoom
            guard !isAddingPage else { return }
            guard scrollView.zoomScale >= 0.9 && scrollView.zoomScale <= 1.1 else { return }

            let contentHeight = scrollView.contentSize.height
            let offsetY = scrollView.contentOffset.y
            let viewHeight = scrollView.bounds.height

            // Only add if scrolled near the bottom
            if offsetY + viewHeight > contentHeight - 50 && contentHeight > 0 && offsetY > 0 {
                isAddingPage = true
                addPage()
            }
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
