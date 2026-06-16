import XCTest

/// Base class for all UI tests. Launches the app in QA/test mode and exposes
/// small helpers so individual tests (and the agents that write them) stay short
/// and read like a QA script: launch → interact → assert.
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
}
