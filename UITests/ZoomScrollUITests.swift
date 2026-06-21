import XCTest

final class ZoomScrollUITests: QABase {

    private func openZoomScroll() {
        open(QAID.zoomScrollLink)
    }

    func testPinchChangesScale() {
        openZoomScroll()
        let surface = app.otherElements[QAID.zoomSurface]
        XCTAssertTrue(surface.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts[QAID.zoomScale].label, "Scale: 1.00")

        surface.pinchToZoom(scale: 2.0)

        XCTAssertNotEqual(app.staticTexts[QAID.zoomScale].label, "Scale: 1.00")
    }

    func testPanChangesOffset() {
        openZoomScroll()
        let surface = app.otherElements[QAID.zoomSurface]
        XCTAssertTrue(surface.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts[QAID.panOffset].label, "Offset: 0, 0")

        surface.pan(from: CGVector(dx: 0.5, dy: 0.5), to: CGVector(dx: 0.2, dy: 0.2))

        XCTAssertNotEqual(app.staticTexts[QAID.panOffset].label, "Offset: 0, 0")
    }

    func testResetRestoresTransform() {
        openZoomScroll()
        let surface = app.otherElements[QAID.zoomSurface]
        XCTAssertTrue(surface.waitForExistence(timeout: 5))

        surface.pan(from: CGVector(dx: 0.5, dy: 0.5), to: CGVector(dx: 0.2, dy: 0.2))
        app.buttons[QAID.resetTransform].tap()

        XCTAssertEqual(app.staticTexts[QAID.zoomScale].label, "Scale: 1.00")
        XCTAssertEqual(app.staticTexts[QAID.panOffset].label, "Offset: 0, 0")
    }
}
