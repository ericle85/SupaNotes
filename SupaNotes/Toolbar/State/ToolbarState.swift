import SwiftUI
import UIKit

enum ActiveTool: String, Codable, Equatable {
    case pen, eraser
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

    /// All toolbar icons that are drawing tools (pen, eraser) — not colors.
    var toolIcons: [ToolbarIcon] {
        toolbarIcons.filter { $0.type != .color }
    }

    /// All toolbar icons that are colors.
    var colorIcons: [ToolbarIcon] {
        toolbarIcons.filter { $0.type == .color }
    }

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

    func save() {
        ToolbarPersistence.save(self)
    }

    func resetToDefaults() {
        toolbarIcons = ToolbarPersistence.defaultIcons()
        sectionOrder = [.undoRedo, .tools, .colors]
        showUndoRedo = true
    }
}
