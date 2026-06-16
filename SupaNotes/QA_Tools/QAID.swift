import Foundation

/// Canonical accessibility identifiers for UI elements that QA (UI tests and
/// agents driving the simulator) needs to locate. Keep every testable element's
/// identifier here so the app and the UITests target share one source of truth.
///
/// The UITests target keeps a mirror of these strings (it's a separate module);
/// if you add an identifier here, add it there too.
enum QAID {
    static let displayedNumber = "displayedNumber"

    static func numberButton(_ n: Int) -> String { "numberButton.\(n)" }
}
