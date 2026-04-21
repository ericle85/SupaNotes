import SwiftUI
import UIKit

enum ActiveTool: String, Codable, Equatable {
    case pen, eraser, highlighter, lasso
}

enum ToolbarSection: String, Codable, CaseIterable, Identifiable {
    case undoRedo, tools, colors
    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .undoRedo: return "Undo / Redo"
        case .tools: return "Tools"
        case .colors: return "Colors"
        }
    }
}

@Observable
final class ToolbarState {
    var colorSelectedByUser: Color = .black
    var currentlyActiveTool: ActiveTool = .pen
    var toolbarIcons: [ToolbarIcon] = []
    var toolUsedPreviously: ActiveTool = .eraser
    var sectionOrder: [ToolbarSection] = [.undoRedo, .tools, .colors]
    var showUndoRedo: Bool = true
    var showCustomization: Bool = false
    var previewDraggedIconID: UUID?
    var previewDraggedSection: ToolbarSection?

    func switchToPreviousTool() {
        let currentTool = currentlyActiveTool
        currentlyActiveTool = toolUsedPreviously
        toolUsedPreviously = currentTool
    }

    init() {
        ToolbarPersistence.load(into: self)
    }

    func instrumentWidth(for type: ToolType) -> CGFloat {
        let matchingIcon = toolbarIcons.first(where: { icon in icon.type == type })
        return matchingIcon?.instrumentSettings?.width ?? WritingInstrumentSettings.pen().width
    }

    var currentDrawingTool: DrawingTool {
        switch currentlyActiveTool {
        case .pen, .highlighter, .lasso:
            return .pen(
                color: UIColor(colorSelectedByUser),
                width: instrumentWidth(for: .pen)
            )
        case .eraser:
            return .eraser(width: instrumentWidth(for: .eraser))
        }
    }

    func save(colorScheme: ColorScheme) {
        ToolbarPersistence.save(self, colorScheme: colorScheme)
    }

    func resetToDefaults(colorScheme: ColorScheme) {
        toolbarIcons = ToolbarPersistence.defaultIcons(colorScheme: colorScheme)
        sectionOrder = [.undoRedo, .tools, .colors]
        showUndoRedo = true
    }
}
