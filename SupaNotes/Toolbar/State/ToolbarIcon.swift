import SwiftUI

// MARK: - Toolbar Layout Constants

enum ToolbarConstants {
    static let tapTargetSize: CGFloat = 38
}

// MARK: - Tool Type Enum

enum ToolType: String, Codable, CaseIterable {
    case color
    case pen = "pencil" // Raw value preserved for backwards compatibility
    case eraser
    case highlighter
    case lasso

    var iconName: String {
        switch self {
        case .color: return "paintpalette.fill"
        case .pen: return "pencil"
        case .eraser: return "eraser.fill"
        case .highlighter: return "highlighter"
        case .lasso: return "lasso"
        }
    }

    var displayName: String {
        switch self {
        case .pen: return "Pen"
        default: return String(describing: self).capitalized
        }
    }

    var isWritingInstrument: Bool {
        switch self {
        case .pen, .eraser, .highlighter: return true
        default: return false
        }
    }
}

// MARK: - Toolbar Icon Model

struct ToolbarIcon: Identifiable, Equatable, Codable {
    let id: UUID
    let type: ToolType

    var colorData: CodableColor?
    var name: String
    var instrumentSettings: WritingInstrumentSettings?

    var color: Color? {
        colorData?.toColor()
    }

    enum CodingKeys: String, CodingKey {
        case id, type, colorData, name, instrumentSettings
    }

    static let essentialTypes: Set<ToolType> = [.color, .pen, .eraser]

    var isEssential: Bool {
        Self.essentialTypes.contains(type)
    }

    func isEquivalent(to other: ToolbarIcon, colorScheme: ColorScheme) -> Bool {
        guard type == other.type else { return false }
        if type == .color, let c1 = color, let c2 = other.color {
            return c1.isSimilar(to: c2, colorScheme: colorScheme)
        }
        return type != .color
    }

    static func colorIcon(_ color: Color, name: String = "Color", colorScheme: ColorScheme) -> ToolbarIcon {
        ToolbarIcon(
            id: UUID(),
            type: .color,
            colorData: CodableColor(color: color, colorScheme: colorScheme),
            name: name
        )
    }

    static func toolIcon(_ type: ToolType, name: String? = nil) -> ToolbarIcon {
        let settings: WritingInstrumentSettings? = switch type {
        case .pen: .pen()
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
    mutating func appendToZone(_ icon: ToolbarIcon) {
        if icon.type == .color {
            append(icon)
        } else {
            if let lastToolIndex = lastIndex(where: { $0.type != .color }) {
                insert(icon, at: lastToolIndex + 1)
            } else {
                insert(icon, at: 0)
            }
        }
    }
}
