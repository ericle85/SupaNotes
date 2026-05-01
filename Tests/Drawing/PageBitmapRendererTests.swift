import Testing
import UIKit
@testable import SupaNotes

// Unit tests for PageBitmapRenderer — verifies that render() produces correctly
// sized, non-nil images for different page configurations.
@Suite struct PageBitmapRendererTests {

    // MARK: - Helpers

    private func makePage(template: PageTemplate = .white) -> Page {
        let page = Page(orderIndex: 0)
        page.templateRaw = template.rawValue
        return page
    }

    // MARK: - Tests

    // Empty page (no PDF, no drawing) should produce an image at page size × scale.
    @Test func render_emptyPage_returnsCorrectSize() {
        let page = makePage()
        let image = PageBitmapRenderer.render(page: page, scale: 0.5)
        let expectedWidth = page.size.width
        let expectedHeight = page.size.height
        // UIGraphicsImageRenderer size is in points; scale is the backing scale factor.
        #expect(image.size.width == expectedWidth)
        #expect(image.size.height == expectedHeight)
        #expect(image.scale == 0.5)
    }

    // Dark template page should still render without crashing.
    @Test func render_darkTemplate_succeeds() {
        let page = makePage(template: .dark)
        let image = PageBitmapRenderer.render(page: page)
        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
    }

    // Page with drawing data should render without error.
    @Test func render_withDrawingData_succeeds() {
        let page = makePage()
        // DrawingCodec.encode of an empty drawing produces valid data.
        page.drawingData = DrawingCodec.encode(currentPage: DrawingCodec.decode(data: Data()))
        let image = PageBitmapRenderer.render(page: page)
        #expect(image.size.width > 0)
    }

    // Default scale should be 0.5.
    @Test func defaultScale_isHalf() {
        #expect(PageBitmapRenderer.defaultScale == 0.5)
    }
}
