import CoreGraphics

/// Pure math helpers for page positions and scroll sizing.
enum PageLayout {
    static func containerWidth(pageW: CGFloat, gap: CGFloat, scrollWidth: CGFloat) -> CGFloat {
        max(pageW + gap * 2, scrollWidth)
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
        (0 ..< count).map {
            pageFrame(index: $0, pageW: pageW, pageH: pageH, gap: gap, containerWidth: containerWidth)
        }
    }

    /// Center content when it is smaller than the visible scroll area.
    static func centeringOrigin(contentSize: CGSize, scrollBounds: CGSize) -> CGPoint {
        CGPoint(
            x: max(0, (scrollBounds.width - contentSize.width) / 2),
            y: max(0, (scrollBounds.height - contentSize.height) / 2)
        )
    }

    /// Expected scrollable content size after zoom is applied.
    static func scrollContentSize(containerSize: CGSize, zoomScale: CGFloat) -> CGSize {
        CGSize(width: containerSize.width * zoomScale, height: containerSize.height * zoomScale)
    }
}
