import XCTest

final class DrawingUITests: QABase {

    private func openDrawing() {
        open(QAID.drawingLink)
        XCTAssertTrue(app.otherElements[QAID.drawCanvas].waitForExistence(timeout: 5))
    }

    func testFingerDragDoesNotDraw() {
        openDrawing()
        XCTAssertEqual(app.staticTexts[QAID.strokeCount].label, "Strokes: 0")
        app.otherElements[QAID.drawCanvas].pan(from: CGVector(dx: 0.5, dy: 0.2),
                                               to: CGVector(dx: 0.5, dy: 0.8))
        XCTAssertEqual(app.staticTexts[QAID.strokeCount].label, "Strokes: 0")
    }

    func testInjectedPencilStrokeDraws() {
        openDrawing()
        XCTAssertEqual(app.staticTexts[QAID.strokeCount].label, "Strokes: 0")
        app.injectPencilStroke()
        XCTAssertEqual(app.staticTexts[QAID.strokeCount].label, "Strokes: 1")
    }

    func testMultiplePencilStrokesAndClear() {
        openDrawing()
        app.injectPencilStroke()
        app.injectPencilStroke()
        XCTAssertEqual(app.staticTexts[QAID.strokeCount].label, "Strokes: 2")
        app.buttons[QAID.clearStrokes].tap()
        XCTAssertEqual(app.staticTexts[QAID.strokeCount].label, "Strokes: 0")
    }

    func testCustomPencilStrokeViaBridge() {
        openDrawing()
        app.injectPencilStroke([CGVector(dx: 0.1, dy: 0.1), CGVector(dx: 0.9, dy: 0.9)])
        XCTAssertEqual(app.staticTexts[QAID.strokeCount].label, "Strokes: 1")
    }
}
