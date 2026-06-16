import Foundation

/// Central read point for QA/test-mode toggles passed in at launch.
///
/// UI tests (and agents driving the simulator) set these via
/// `app.launchArguments` / `app.launchEnvironment` in XCUITest. The app reads
/// them here so test-only affordances stay out of normal runtime behavior.
///
/// Forward-looking: the canvas will be Apple-Pencil-draw-only with finger used
/// for pan/scroll. The simulator has no Pencil, so when `isUITestMode` is on the
/// canvas should accept finger/mouse drags as pencil strokes — letting XCUITest
/// `press(forDuration:thenDragTo:)` gestures produce real drawings during QA.
enum QAEnvironment {
    /// True when the app was launched by the UITests target / an agent QA run.
    static let isUITestMode = ProcessInfo.processInfo.arguments.contains("-UITEST")

    /// Launch argument string the test side passes to enable `isUITestMode`.
    static let uiTestFlag = "-UITEST"
}
