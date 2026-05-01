import UIKit

// Manages the active window of DrawingCanvasView instances — creates views for
// pages entering the buffer zone and removes views for pages leaving it.
final class PageRecycler {

    // Number of extra pages to keep loaded beyond the visible rect on each side.
    private let bufferCount: Int

    // Currently active page indices mapped to their canvas views.
    private(set) var activeViews: [Int: DrawingCanvasView] = [:]

    // Page data and geometry from the last rebuild.
    private(set) var sortedPages: [Page] = []
    private(set) var pageFrames: [CGRect] = []

    // Called to create a canvas for a page at a given index and frame.
    var createCanvas: ((_ page: Page, _ frame: CGRect) -> DrawingCanvasView)?

    // Called before a canvas is removed (e.g. to flush strokes).
    var willRemoveCanvas: ((_ canvas: DrawingCanvasView) -> Void)?

    init(bufferCount: Int = 1) {
        self.bufferCount = bufferCount
    }

    // MARK: - Configuration

    // Set page list and geometry after a rebuild.
    func configure(sortedPages: [Page], pageFrames: [CGRect]) {
        self.sortedPages = sortedPages
        self.pageFrames = pageFrames
    }

    // Remove all active views and fire willRemoveCanvas for each.
    func removeAll() {
        for (_, canvas) in activeViews {
            willRemoveCanvas?(canvas)
            canvas.removeFromSuperview()
        }
        activeViews.removeAll()
    }

    // MARK: - Active Window

    // Compute which pages should be active based on visible rect, diff against
    // current set, and create/remove views accordingly.
    func updateActiveWindow(visibleRect: CGRect, containerView: UIView) {
        guard !pageFrames.isEmpty else { return }

        // Expand visible rect by buffer height on each side.
        let bufferHeight = averagePageHeight() * CGFloat(bufferCount)
        let expandedRect = visibleRect.insetBy(dx: 0, dy: -bufferHeight)

        // Diff needed vs current.
        let neededIndices = indicesInRect(expandedRect)
        let currentIndices = Set(activeViews.keys)

        // Remove views no longer needed.
        for index in currentIndices.subtracting(neededIndices) {
            guard let canvas = activeViews.removeValue(forKey: index) else { continue }
            willRemoveCanvas?(canvas)
            canvas.removeFromSuperview()
        }

        // Create views for newly needed pages.
        for index in neededIndices.subtracting(currentIndices).sorted() {
            guard index < sortedPages.count, index < pageFrames.count else { continue }
            guard let canvas = createCanvas?(sortedPages[index], pageFrames[index]) else { continue }
            canvas.tag = index
            containerView.addSubview(canvas)
            activeViews[index] = canvas
        }
    }

    // MARK: - Queries

    // All active canvas views sorted by page index.
    var allActiveCanvases: [DrawingCanvasView] {
        activeViews.values.sorted { $0.tag < $1.tag }
    }

    // Canvas for a specific page index, if active.
    func canvas(at index: Int) -> DrawingCanvasView? {
        activeViews[index]
    }

    // MARK: - Helpers

    // Average page height for buffer calculation.
    func averagePageHeight() -> CGFloat {
        guard !pageFrames.isEmpty else { return 0 }
        let total = pageFrames.reduce(CGFloat(0)) { $0 + $1.height }
        return total / CGFloat(pageFrames.count)
    }

    // Compute which page indices intersect the given rect.
    func indicesInRect(_ rect: CGRect) -> Set<Int> {
        Set(
            pageFrames.enumerated()
                .filter { $0.element.intersects(rect) }
                .map(\.offset)
        )
    }
}
