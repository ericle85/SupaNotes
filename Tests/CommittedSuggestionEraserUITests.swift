import XCTest

final class CommittedSuggestionEraserUITests: XCTestCase {
  func testEraserTapRemovesCommittedSuggestion() {
    let app = XCUIApplication()
    app.launchArguments = [
      "--ui-test-committed-suggestion",
    ]
    app.launch()

    let suggestion = app.otherElements["committed-suggestion"]
    XCTAssertTrue(suggestion.waitForExistence(timeout: 5))

    suggestion.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

    XCTAssertFalse(suggestion.waitForExistence(timeout: 1))
  }
}
