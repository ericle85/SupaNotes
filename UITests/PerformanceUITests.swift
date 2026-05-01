import XCTest

// Measures real-device CPU, memory, and wall-clock cost of opening and
// scrolling a 200-page note. Run on both the PageRecycler branch and the
// pre-recycler commit to compare.
//
// Launch arg -perf-stress tells the app to create an in-memory store
// with a single "PerfStressNote" containing 200 blank pages.
final class PerformanceUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-perf-stress"]
    }

    // MARK: - Open note

    // Measures the time from tapping a 200-page note tile to the first
    // canvas becoming visible. Captures wall clock, CPU, and memory.
    func test_openLargeNote() {
        let metrics: [XCTMetric] = [
            XCTClockMetric(),
            XCTCPUMetric(),
            XCTMemoryMetric()
        ]

        // Cold-launch the app once outside the measure block so the home
        // grid is ready. We re-launch inside measure for each iteration.
        measure(metrics: metrics) {
            app.launch()

            let tile = app.buttons["noteTile.PerfStressNote"]
            guard tile.waitForExistence(timeout: 10) else {
                XCTFail("Stress note tile not found")
                return
            }
            tile.tap()

            // Wait for editor to fully load.
            sleep(3)
        }
    }

    // MARK: - Full scroll

    // Opens the 200-page note, then measures the cost of rapid long drags
    // from top to bottom. Exercises the recycler's create/remove cycle
    // (or, without recycler, stresses all 200 views).
    func test_scrollThroughAllPages() {
        app.launch()

        let tile = app.buttons["noteTile.PerfStressNote"]
        guard tile.waitForExistence(timeout: 10) else {
            XCTFail("Stress note tile not found")
            return
        }
        tile.tap()

        // Wait for editor to fully load.
        sleep(3)

        let window = app.windows.firstMatch
        let top = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
        let bottom = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))

        let metrics: [XCTMetric] = [
            XCTClockMetric(),
            XCTCPUMetric(),
            XCTMemoryMetric()
        ]

        let options = XCTMeasureOptions()
        options.iterationCount = 1
        measure(metrics: metrics, options: options) {
            // Scroll for 15s then stop.
            let deadline = Date().addingTimeInterval(15)
            while Date() < deadline {
                bottom.press(forDuration: 0, thenDragTo: top, withVelocity: 5000, thenHoldForDuration: 0)
            }
        }
    }

    // MARK: - Memory at rest

    // Opens the 200-page note, scrolls to the middle, waits for views
    // to settle, then measures steady-state memory. With the recycler
    // only ~3 views should be alive; without, all 200.
    func test_memoryAtRestMidScroll() {
        app.launch()

        let tile = app.buttons["noteTile.PerfStressNote"]
        guard tile.waitForExistence(timeout: 10) else {
            XCTFail("Stress note tile not found")
            return
        }
        tile.tap()

        // Wait for editor to fully load.
        sleep(3)

        let window = app.windows.firstMatch
        let top = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
        let bottom = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))

        // Scroll to roughly the middle (~5 fast drags).
        for _ in 0..<5 {
            bottom.press(forDuration: 0, thenDragTo: top, withVelocity: 5000, thenHoldForDuration: 0)
        }

        // Let layout settle.
        sleep(2)

        // Measure steady-state memory after scrolling to the middle.
        let metrics: [XCTMetric] = [XCTMemoryMetric()]
        measure(metrics: metrics) {
            // Hold position — just measuring resting memory footprint.
            sleep(3)
        }
    }
}
