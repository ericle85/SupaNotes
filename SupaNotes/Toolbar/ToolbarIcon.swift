import SwiftUI

// MARK: - Toolbar Layout Constants
enum ToolbarConstants {
    /// Minimum touch target size per Apple HIG (44×44 pt).
    static let tapTargetSize: CGFloat = 38
}

// MARK: - Tool Type Enum
enum ToolType: String, Codable, CaseIterable {
    case color
    case pencil
    case eraser
    case highlighter
    case lasso

    // SF Symbols for each tool type
    var iconName: String {
        switch self {
        case .color: return "paintpalette.fill"
        case .pencil: return "pencil"
        case .eraser: return "eraser.fill"
        case .highlighter: return "highlighter"
        case .lasso: return "lasso"
        }
    }

    var displayName: String {
        rawValue.capitalized
    }

    var isWritingInstrument: Bool {
        switch self {
        case .pencil, .eraser, .highlighter: return true
        default: return false
        }
    }
}

// MARK: - Toolbar Icon Model (Generic for all tools)
struct ToolbarIcon: Identifiable, Equatable, Codable {
    let id: UUID
    let type: ToolType

    // Type-specific properties
    var colorData: CodableColor?  // For color tools (Codable)
    var name: String
    var instrumentSettings: WritingInstrumentSettings?

    // Convenience property to extract Color from colorData
    var color: Color? {
        colorData?.toColor()
    }

    // Custom coding keys to exclude computed property
    enum CodingKeys: String, CodingKey {
        case id, type, colorData, name, instrumentSettings
    }

    // Essential tool types (must always have at least 1 of each)
    static let essentialTypes: Set<ToolType> = [.color, .pencil, .eraser]

    // Check if this icon's type is essential
    var isEssential: Bool {
        Self.essentialTypes.contains(type)
    }

    /// Generic duplicate detection.
    /// - Color icons: delegates to `Color.isSimilar`
    /// - All other types: two icons with the same `type` are duplicates
    func isEquivalent(to other: ToolbarIcon, colorScheme: ColorScheme) -> Bool {
        guard type == other.type else { return false }
        if type == .color, let c1 = color, let c2 = other.color {
            return c1.isSimilar(to: c2, colorScheme: colorScheme)
        }
        return type != .color
    }

    // Helper to create a color icon
    static func colorIcon(_ color: Color, name: String = "Color", colorScheme: ColorScheme) -> ToolbarIcon {
        ToolbarIcon(
            id: UUID(),
            type: .color,
            colorData: CodableColor(color: color, colorScheme: colorScheme),
            name: name
        )
    }

    // Helper to create a tool icon
    static func toolIcon(_ type: ToolType, name: String? = nil) -> ToolbarIcon {
        let settings: WritingInstrumentSettings? = switch type {
        case .pencil: .pen()
        case .eraser: .eraser()
        case .highlighter: .highlighter()
        default: nil
        }
        return ToolbarIcon(
            id: UUID(),
            type: type,
            name: name ?? type.displayName,
            instrumentSettings: settings
        )
    }
}

// MARK: - Zone-aware insertion
extension Array where Element == ToolbarIcon {
    /// Inserts the icon at the end of its zone (tools before colors).
    mutating func appendToZone(_ icon: ToolbarIcon) {
        if icon.type == .color {
            // Append at the very end (color zone is last)
            append(icon)
        } else {
            // Insert after the last non-color icon
            if let lastToolIndex = lastIndex(where: { $0.type != .color }) {
                insert(icon, at: lastToolIndex + 1)
            } else {
                insert(icon, at: 0)
            }
        }
    }
}
