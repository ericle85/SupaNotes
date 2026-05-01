import XCTest

// End-to-end test for the multi-tab editor.
//
// Reproduces the bug where switching from one open note tab to another
// leaves the destination tab unrendered (and switching back also fails).
//
// The app is launched with -uitest-seed-tabs which:
//   - Uses an in-memory SwiftData store (no disk pollution between runs)
//   - Pre-creates two notes titled "TabUITestA" and "TabUITestB"
//
// The test then opens both notes (so both appear in the tab bar), taps
// each tab, and asserts that the canvas tagged with that note's title is
// actually on screen.
final class TabSwitchingUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func test_switchingBetweenTabs_rendersCorrectNoteCanvas() {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-seed-tabs"]
        app.launch()

        // Open note A from the home grid → editor opens with tab [A].
        let tileA = app.buttons["noteTile.TabUITestA"]
        XCTAssertTrue(tileA.waitForExistence(timeout: 5), "Seeded note A tile should appear on home screen")
        tileA.tap()

        // Confirm canvas A rendered, then go back to home.
        let canvasA = app.descendants(matching: .any)["canvas.TabUITestA"]
        XCTAssertTrue(canvasA.firstMatch.waitForExistence(timeout: 5), "Note A canvas should render after first open")
        navigateBackToHome(app: app)

        // Open note B → tab bar should now contain [A, B].
        let tileB = app.buttons["noteTile.TabUITestB"]
        XCTAssertTrue(tileB.waitForExistence(timeout: 5), "Seeded note B tile should appear on home screen")
        tileB.tap()

        let canvasB = app.descendants(matching: .any)["canvas.TabUITestB"]
        XCTAssertTrue(canvasB.firstMatch.waitForExistence(timeout: 5), "Note B canvas should render after first open")

        // Both tabs should be visible in the bar.
        let tabA = app.buttons["tab.TabUITestA"]
        let tabB = app.buttons["tab.TabUITestB"]
        XCTAssertTrue(tabA.waitForExistence(timeout: 2), "Tab A should be visible in tab bar")
        XCTAssertTrue(tabB.exists, "Tab B should be visible in tab bar")

        // === The actual bug repro ===

        // Switch from B → A. Canvas A must render.
        tabA.tap()
        XCTAssertTrue(
            canvasA.firstMatch.waitForExistence(timeout: 3),
            "BUG: switching to tab A did not render note A's canvas"
        )

        // Switch back A → B. Canvas B must render.
        tabB.tap()
        XCTAssertTrue(
            canvasB.firstMatch.waitForExistence(timeout: 3),
            "BUG: switching back to tab B did not render note B's canvas"
        )
    }

    // The editor shows a floating chevron-left back button as the only way
    // out — there is no nav bar. Find it by SF Symbol name + position.
    private func navigateBackToHome(app: XCUIApplication) {
        // The back button is an Image(systemName: "chevron.left") inside a Button —
        // XCUITest exposes it as a button whose label is the symbol name.
        let backButton = app.buttons.matching(identifier: "chevron.left").firstMatch
        if backButton.waitForExistence(timeout: 2) {
            backButton.tap()
            return
        }
        // Fallback: first button at top-leading area of editor.
        let editorButtons = app.buttons.allElementsBoundByIndex
        if let topLeft = editorButtons.first(where: { $0.frame.minX < 100 && $0.frame.minY < 200 }) {
            topLeft.tap()
        }
    }
}
