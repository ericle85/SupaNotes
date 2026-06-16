import Foundation

/// Mirror of `QAID` in the app target. UITests is a separate module and cannot
/// import the app's internal types, so the identifier strings are duplicated
/// here. Keep this in sync with `SupaNotes/QAID.swift`.
enum QAID {
    static let displayedNumber = "displayedNumber"

    static func numberButton(_ n: Int) -> String { "numberButton.\(n)" }
}
