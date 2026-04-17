import UIKit

enum PageTemplate: String, CaseIterable, Codable, Sendable {
    case white
    case dark

    var backgroundColor: UIColor {
        switch self {
        case .white: return .white
        case .dark: return UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .white: return .light
        case .dark: return .dark
        }
    }

    var displayName: String {
        switch self {
        case .white: return "White"
        case .dark: return "Dark"
        }
    }
}
