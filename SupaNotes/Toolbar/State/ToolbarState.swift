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
    var selectedColor: Color = .black
    var activeTool: ActiveTool = .pen
    var toolbarIcons: [ToolbarIcon] = []
    var previousTool: ActiveTool = .eraser
    var sectionOrder: [ToolbarSection] = [.undoRedo, .tools, .colors]
    var showUndoRedo: Bool = true
    var showCustomization: Bool = false

    func switchToPreviousTool() {
        let oldTool = activeTool
        activeTool = previousTool
        previousTool = oldTool
    }

    init() {
        ToolbarPersistence.load(into: self)
    }

    func instrumentWidth(for type: ToolType) -> CGFloat {
        toolbarIcons.first(where: { $0.type == type })?.instrumentSettings?.width
            ?? WritingInstrumentSettings.pen().width
    }

    var currentPKTool: PKTool {
        let scale = PageConstants.renderScale
        switch activeTool {
        case .pen:
            return PKInkingTool(.pen, color: UIColor(selectedColor), width: instrumentWidth(for: .pen) * scale)
        case .eraser:
            return PKEraserTool(.bitmap, width: instrumentWidth(for: .eraser) * scale)
        case .highlighter:
            return PKInkingTool(.marker, color: UIColor(selectedColor), width: instrumentWidth(for: .highlighter) * scale)
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
