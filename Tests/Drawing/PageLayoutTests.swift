import Testing
import CoreGraphics
@testable import SupaNotes

/// Every page centerX equals the content midX; containerView origin centers
/// the container inside the scroll bounds whenever it's smaller.
struct PageLayoutTests {

    private let pageW: CGFloat = 612
    private let pageH: CGFloat = 792
    private let gap: CGFloat = 24

    @Test("All pages share same centerX", arguments: [1, 2, 3, 5, 10])
    func allPagesCentered_sameCenterX(pageCount: Int) throws {
        let scrollWidth: CGFloat = 820
        let cw = PageLayout.containerWidth(pageW: pageW, gap: gap, scrollWidth: scrollWidth)
        let centers = (0..<pageCount).map { i in
            PageLayout.pageFrame(index: i, pageW: pageW, pageH: pageH, gap: gap, containerWidth: cw).midX
        }
        let expected = PageLayout.pageCenterX(pageW: pageW, gap: gap, containerWidth: cw)
        for c in centers { #expect(abs(c - expected) < 0.001) }
    }

    @Test("Adding pages does not shift centerX", arguments: [1, 2, 5])
    func addingPages_doesNotShiftCenterX(added: Int) throws {
        let scrollWidth: CGFloat = 820
        let cw = PageLayout.containerWidth(pageW: pageW, gap: gap, scrollWidth: scrollWidth)
        let first = PageLayout.pageFrame(index: 0, pageW: pageW, pageH: pageH, gap: gap, containerWidth: cw).midX
        let later = PageLayout.pageFrame(index: added, pageW: pageW, pageH: pageH, gap: gap, containerWidth: cw).midX
        #expect(abs(first - later) < 0.001)
    }

    // MARK: - centeringOrigin (Apple canonical zoom centering)

    @Test("Smaller content is centered with padding")
    func centeringOrigin_pads_whenContentSmaller() {
        let origin = PageLayout.centeringOrigin(
            contentSize: CGSize(width: 612, height: 792),
            scrollBounds: CGSize(width: 820, height: 1180)
        )
        #expect(abs(origin.x - 104) < 0.001)
        #expect(abs(origin.y - 194) < 0.001)
    }

    @Test("Larger content pins to zero")
    func centeringOrigin_pinsToZero_whenContentLarger() {
        let origin = PageLayout.centeringOrigin(
            contentSize: CGSize(width: 2000, height: 3000),
            scrollBounds: CGSize(width: 820, height: 1180)
        )
        #expect(origin == .zero)
    }

    @Test("Equal content stays at zero")
    func centeringOrigin_equalSize() {
        let size = CGSize(width: 820, height: 1180)
        #expect(PageLayout.centeringOrigin(contentSize: size, scrollBounds: size) == .zero)
    }
}
