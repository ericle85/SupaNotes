import SwiftUI
import PencilKit

enum ActiveTool: String, Codable, Equatable {
    case pen, eraser, highlighter, lasso
}

@Observable
final class ToolbarState {
    var selectedColor: Color = .black
    var activeTool: ActiveTool = .pen
    var toolbarIcons: [ToolbarIcon] = []
    var previousTool: ActiveTool = .eraser

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
        switch activeTool {
        case .pen:
            return PKInkingTool(.pen, color: UIColor(selectedColor), width: instrumentWidth(for: .pen))
        case .eraser:
            return PKEraserTool(.bitmap, width: instrumentWidth(for: .eraser))
        case .highlighter:
            return PKInkingTool(.marker, color: UIColor(selectedColor), width: instrumentWidth(for: .highlighter))
        case .lasso:
            return PKLassoTool()
        }
    }

    func save(colorScheme: ColorScheme) {
        ToolbarPersistence.save(self, colorScheme: colorScheme)
    }
}
