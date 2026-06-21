import XCTest

final class NumberButtonsUITests: QABase {

    private func openNumbers() {
        open(QAID.numbersLink)
    }

    func testButtonsStartWithNoSelection() {
        openNumbers()
        let display = app.staticTexts[QAID.displayedNumber]
        XCTAssertTrue(display.waitForExistence(timeout: 5))
        XCTAssertEqual(display.label, "—")
    }

    func testTappingEachButtonDisplaysItsNumber() {
        openNumbers()
        let display = app.staticTexts[QAID.displayedNumber]
        XCTAssertTrue(display.waitForExistence(timeout: 5))

        for number in 1...3 {
            app.buttons[QAID.numberButton(number)].tap()
            XCTAssertEqual(display.label, "\(number)")
        }
    }
}
