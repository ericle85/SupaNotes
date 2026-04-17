import CoreGraphics

/// Pure geometry helpers for page layout. No UIKit, no side effects.
enum PageLayout {

    static func containerSize(pageCount: Int, pageW: CGFloat, pageH: CGFloat, gap: CGFloat, scrollWidth: CGFloat) -> CGSize {
        CGSize(
            width: max(pageW + gap * 2, scrollWidth),
            height: CGFloat(pageCount) * pageH + CGFloat(max(0, pageCount - 1)) * gap + gap * 2
        )
    }

    static func containerWidth(pageW: CGFloat, gap: CGFloat, scrollWidth: CGFloat) -> CGFloat {
        max(pageW + gap * 2, scrollWidth)
    }

    static func containerHeight(pageCount: Int, pageH: CGFloat, gap: CGFloat) -> CGFloat {
        CGFloat(pageCount) * pageH + CGFloat(max(0, pageCount - 1)) * gap + gap * 2
    }

    static func pageFrame(index: Int, pageW: CGFloat, pageH: CGFloat, gap: CGFloat, containerWidth: CGFloat) -> CGRect {
        CGRect(
            x: (containerWidth - pageW) / 2,
            y: gap + CGFloat(index) * (pageH + gap),
            width: pageW,
            height: pageH
        )
    }

    static func pageFrames(count: Int, pageW: CGFloat, pageH: CGFloat, gap: CGFloat, containerWidth: CGFloat) -> [CGRect] {
        (0..<count).map { pageFrame(index: $0, pageW: pageW, pageH: pageH, gap: gap, containerWidth: containerWidth) }
    }

    /// Apple's canonical zoom-centering: pad when content smaller, pin to 0 when larger.
    static func centeringOrigin(contentSize: CGSize, scrollBounds: CGSize) -> CGPoint {
        CGPoint(
            x: max(0, (scrollBounds.width - contentSize.width) / 2),
            y: max(0, (scrollBounds.height - contentSize.height) / 2)
        )
    }

    /// Effective scroll content size under zoom. UIScrollView normally derives
    /// this from viewForZooming's bounds × zoomScale; we mirror that pure-fn-ly.
    static func scrollContentSize(containerSize: CGSize, zoomScale: CGFloat) -> CGSize {
        CGSize(width: containerSize.width * zoomScale, height: containerSize.height * zoomScale)
    }

    static func pageCenterX(pageW: CGFloat, gap: CGFloat, containerWidth: CGFloat) -> CGFloat {
        pageFrame(index: 0, pageW: pageW, pageH: 0, gap: gap, containerWidth: containerWidth).midX
    }
}
