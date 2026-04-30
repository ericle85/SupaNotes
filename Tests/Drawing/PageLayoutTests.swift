import Testing
import CoreGraphics
@testable import SupaNotes

// Tests for the pure math that positions pages inside the scrollable notebook.
struct PageLayoutTests {

    // Standard letter-size page used across most tests.
    private let letter = CGSize(width: 612, height: 792)
    private let gap: CGFloat = 24

    // MARK: - Container width

    // 1.1 — Pick the wider of the page or scroll view.
    @Test func containerWidth_picksWiderOption() {
        // Page wider than scroll view → use page width + gaps.
        let wide = PageLayout.containerWidth(
            pageSizes: [CGSize(width: 800, height: 500)], gap: 24, scrollWidth: 600
        )
        #expect(wide == CGFloat(848))

        // Scroll view wider than page → use scroll view width.
        let narrow = PageLayout.containerWidth(
            pageSizes: [CGSize(width: 300, height: 500)], gap: 24, scrollWidth: 600
        )
        #expect(narrow == CGFloat(600))
    }

    // 1.2 — Variable pages: container fits the widest page.
    @Test func containerWidth_variablePages_usesWidest() {
        let sizes: [CGSize] = [
            CGSize(width: 400, height: 500),
            CGSize(width: 700, height: 500),
            CGSize(width: 500, height: 500),
        ]
        // 700 + 24*2 = 748, scroll is 600, so 748 wins.
        let result = PageLayout.containerWidth(pageSizes: sizes, gap: 24, scrollWidth: 600)
        #expect(result == 748)
    }

    // MARK: - Page frame positioning

    // 1.3 — Pages stack vertically with gaps.
    @Test func pageFrames_stackVertically() {
        let sizes = [letter, letter, letter]
        let cw = PageLayout.containerWidth(pageSizes: sizes, gap: gap, scrollWidth: 700)
        let frames = PageLayout.pageFrames(pageSizes: sizes, gap: gap, containerWidth: cw)

        // Each page starts one (pageH + gap) lower than the previous.
        #expect(frames[0].origin.y == gap)
        #expect(frames[1].origin.y == gap + letter.height + gap)
        #expect(frames[2].origin.y == gap + 2 * (letter.height + gap))
    }

    // 1.4 — Pages are centered horizontally.
    @Test func pageFrames_centeredHorizontally() {
        let cw: CGFloat = 1000
        let frames = PageLayout.pageFrames(pageSizes: [letter], gap: gap, containerWidth: cw)
        // x should be half the leftover space.
        #expect(frames[0].origin.x == (cw - letter.width) / 2)
    }

    // 1.5 — Variable-size pages: tall page pushes next one further down.
    @Test func pageFrames_variableSizes_stackCorrectly() {
        let sizes: [CGSize] = [
            CGSize(width: 612, height: 400),
            CGSize(width: 612, height: 800),
            CGSize(width: 612, height: 300),
        ]
        let frames = PageLayout.pageFrames(pageSizes: sizes, gap: gap, containerWidth: 700)

        #expect(frames[0].origin.y == gap)
        #expect(frames[1].origin.y == gap + 400 + gap)
        #expect(frames[2].origin.y == gap + 400 + gap + 800 + gap)
    }

    // MARK: - Container height

    // 1.6 — Total height = top gap + all pages + between-gaps + bottom gap.
    @Test func containerHeight_addsAllPagesAndGaps() {
        let sizes: [CGSize] = [
            CGSize(width: 612, height: 400),
            CGSize(width: 612, height: 600),
        ]
        // top gap (24) + 400 + gap (24) + 600 + bottom gap (24) = 1072
        let height = PageLayout.containerHeight(pageSizes: sizes, gap: gap)
        #expect(height == CGFloat(1072))
    }

    // MARK: - Centering origin

    // 1.7 — Small content centers, large content stays at (0,0).
    @Test func centeringOrigin_centersSmallContent() {
        // Content smaller than scroll area → centered.
        let small = PageLayout.centeringOrigin(
            contentSize: CGSize(width: 400, height: 300),
            scrollBounds: CGSize(width: 800, height: 600)
        )
        #expect(small.x == 200)
        #expect(small.y == 150)

        // Content larger than scroll area → (0, 0).
        let big = PageLayout.centeringOrigin(
            contentSize: CGSize(width: 1000, height: 900),
            scrollBounds: CGSize(width: 800, height: 600)
        )
        #expect(big.x == 0)
        #expect(big.y == 0)
    }

    // MARK: - Scroll content size

    // 1.8 — Zooming 2x doubles the scrollable area.
    @Test func scrollContentSize_scalesWithZoom() {
        let base = CGSize(width: 700, height: 1000)
        let at1x = PageLayout.scrollContentSize(containerSize: base, zoomScale: 1)
        #expect(at1x.width == 700)
        #expect(at1x.height == 1000)

        let at2x = PageLayout.scrollContentSize(containerSize: base, zoomScale: 2)
        #expect(at2x.width == 1400)
        #expect(at2x.height == 2000)
    }

    // MARK: - Coordinate conversion (toLetterSpace)

    // 5.1 — Screen corners map to page corners.
    @Test func toLetterSpace_mapsCornersCorrectly() {
        let viewSize = CGSize(width: 500, height: 700)
        let pageSize = CGSize(width: 612, height: 792)

        // Top-left of screen → top-left of page.
        let topLeft = PageLayout.toLetterSpace(.zero, viewSize: viewSize, pageSize: pageSize)
        #expect(topLeft.x == 0)
        #expect(topLeft.y == 0)

        // Bottom-right of screen → bottom-right of page.
        let bottomRight = PageLayout.toLetterSpace(
            CGPoint(x: 500, y: 700), viewSize: viewSize, pageSize: pageSize
        )
        #expect(bottomRight.x == 612)
        #expect(bottomRight.y == 792)

        // Center of screen → center of page.
        let center = PageLayout.toLetterSpace(
            CGPoint(x: 250, y: 350), viewSize: viewSize, pageSize: pageSize
        )
        #expect(center.x == 306)
        #expect(center.y == 396)
    }

    // 5.2 — Zero-size view returns origin, no divide-by-zero.
    @Test func toLetterSpace_zeroSizeView_returnsOrigin() {
        let result = PageLayout.toLetterSpace(
            CGPoint(x: 100, y: 200),
            viewSize: .zero,
            pageSize: CGSize(width: 612, height: 792)
        )
        #expect(result.x == 0)
        #expect(result.y == 0)
    }
}
