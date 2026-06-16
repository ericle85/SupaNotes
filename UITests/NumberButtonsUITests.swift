import XCTest

/// Reference QA test for the 3-button scaffold screen. Demonstrates the loop an
/// agent follows to QA a feature it built: find elements by identifier, tap,
/// then assert the on-screen result.
final class NumberButtonsUITests: QABase {

    func testButtonsStartWithNoSelection() {
        let display = app.staticTexts[QAID.displayedNumber]
        XCTAssertTrue(display.waitForExistence(timeout: 5))
        XCTAssertEqual(display.label, "—")
    }

    func testTappingEachButtonDisplaysItsNumber() {
        let display = app.staticTexts[QAID.displayedNumber]
        XCTAssertTrue(display.waitForExistence(timeout: 5))

        for number in 1...3 {
            app.buttons[QAID.numberButton(number)].tap()
            XCTAssertEqual(display.label, "\(number)",
                           "Tapping button \(number) should display \(number)")
        }
    }
}
