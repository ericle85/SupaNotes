import SwiftUI
import PencilKit

enum ActiveTool: String, Codable, Equatable {
    case pen, eraser, highlighter, lasso
}

enum ToolbarSection: String, Codable, CaseIterable, Identifiable {
    case undoRedo, tools, colors
    var id: String { rawValue }
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
    /// The color currently being used for drawing
    var colorSelectedByUser: Color = .black
    
    /// The tool currently in use (Pen, Eraser, etc.)
    var currentlyActiveTool: ActiveTool = .pen
    
    /// The list of icons (tools and colors) shown in the toolbar
    var toolbarIcons: [ToolbarIcon] = []
    
    /// Keeps track of the last tool used so we can toggle back to it (e.g. pencil <-> eraser)
    var toolUsedPreviously: ActiveTool = .eraser
    
    /// The order in which the different sections of the toolbar appear
    var sectionOrder: [ToolbarSection] = [.undoRedo, .tools, .colors]
    
    /// Whether or not to show the Undo and Redo buttons
    var showUndoRedo: Bool = true
    
    /// Whether the user is currently customizing the toolbar layout
    var showCustomization: Bool = false
    
    /// Temporary ID of an icon being dragged during customization
    var previewDraggedIconID: UUID?
    
    /// Temporary section being dragged during customization
    var previewDraggedSection: ToolbarSection?

    /// Switches the current tool to whatever was being used before
    func switchToPreviousTool() {
        let currentTool = currentlyActiveTool
        currentlyActiveTool = toolUsedPreviously
        toolUsedPreviously = currentTool
    }

    init() {
        // Load the saved toolbar settings from disk
        ToolbarPersistence.load(into: self)
    }

    /// Finds the width setting for a specific tool type (like the Pen's thickness)
    func instrumentWidth(for type: ToolType) -> CGFloat {
        let matchingIcon = toolbarIcons.first(where: { icon in icon.type == type })
        return matchingIcon?.instrumentSettings?.width ?? WritingInstrumentSettings.pen().width
    }

    /// Converts our internal app state into a PencilKit tool that the canvas can use
    var currentPKTool: PKTool {
        switch currentlyActiveTool {
        case .pen:
            return PKInkingTool(.pen, color: UIColor(colorSelectedByUser), width: instrumentWidth(for: .pen))
        case .eraser:
            return PKEraserTool(.bitmap, width: instrumentWidth(for: .eraser))
        case .highlighter:
            return PKInkingTool(.marker, color: UIColor(colorSelectedByUser), width: instrumentWidth(for: .highlighter))
        case .lasso:
            return PKLassoTool()
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
