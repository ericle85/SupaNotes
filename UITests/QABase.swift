import XCTest

class QABase: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITEST"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func open(_ identifier: String) {
        let link = app.buttons[identifier]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
    }
}
