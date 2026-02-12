import SwiftUI

// MARK: - Tool Type Enum
enum ToolType: String, Codable, CaseIterable {
    case color
    case pencil
    case eraser
    case lasso
    case image
    case text

    var iconName: String {
        switch self {
        case .color: return "paintpalette.fill"
        case .pencil: return "pencil.tip"
        case .eraser: return "eraser.fill"
        case .lasso: return "lasso"
        case .image: return "photo"
        case .text: return "textformat"
        }
    }

    var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - Toolbar Icon Model (Generic for all tools)
struct ToolbarIcon: Identifiable, Equatable, Codable {
    let id: UUID
    let type: ToolType

    // Type-specific properties
    var colorData: CodableColor?  // For color tools (Codable)
    var size: CGFloat?            // For pencil/eraser size
    var name: String

    // Computed property for backward compatibility
    var color: Color? {
        colorData?.toColor()
    }

    // Custom coding keys to exclude computed property
    enum CodingKeys: String, CodingKey {
        case id, type, colorData, size, name
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
    /// - Note: If a future type needs distinguishing properties (e.g. pencil sizes),
    ///   add a branch here similar to the color check to compare those properties.
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
        ToolbarIcon(id: UUID(), type: type, name: name ?? type.displayName)
    }
}
