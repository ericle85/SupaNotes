import XCTest
@testable import SupaNotesSwift

final class CommittedSuggestionEraserTests: XCTestCase {
  func testEraserTapRemovesCommittedSuggestion() {
    let pageView = PageView(theme: .adaptive)

    let dummy = AcceptedSuggestionView(mathLabels: [])
    dummy.frame = CGRect(x: 100, y: 100, width: 50, height: 30)
    pageView.addSubview(dummy)

    let before = pageView.subviews.compactMap { $0 as? AcceptedSuggestionView }
    XCTAssertEqual(before.count, 1)

    pageView.eraseCommittedSuggestion(at: CGPoint(x: 105, y: 105))

    let after = pageView.subviews.compactMap { $0 as? AcceptedSuggestionView }
    XCTAssertEqual(after.count, 0)
  }
}
