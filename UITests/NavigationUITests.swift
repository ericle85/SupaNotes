import XCTest

final class NavigationUITests: QABase {

    func testBackButtonReturnsToMenu() {
        open(QAID.drawingLink)
        XCTAssertTrue(app.otherElements[QAID.drawCanvas].waitForExistence(timeout: 5))
        app.buttons[QAID.backButton].tap()
        XCTAssertTrue(app.buttons[QAID.drawingLink].waitForExistence(timeout: 5))
    }

    func testSwipeFromEdgeDoesNotPop() {
        open(QAID.numbersLink)
        XCTAssertTrue(app.staticTexts[QAID.displayedNumber].waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        XCTAssertTrue(app.staticTexts[QAID.displayedNumber].exists)
    }
}
