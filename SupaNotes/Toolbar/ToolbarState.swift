import SwiftUI

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

    private static let selectedColorKey = "toolbar.selectedColor"
    private static let activeToolKey = "toolbar.activeTool"
    private static let toolbarIconsKey = "toolbar.toolbarIcons"

    init() {
        load()
    }

    func instrumentWidth(for type: ToolType) -> CGFloat {
        toolbarIcons.first(where: { $0.type == type })?.instrumentSettings?.width
            ?? WritingInstrumentSettings.pen().width
    }

    func load() {
        let defaults = UserDefaults.standard

        if let data = defaults.data(forKey: Self.toolbarIconsKey),
           let icons = try? JSONDecoder().decode([ToolbarIcon].self, from: data),
           !icons.isEmpty {
            toolbarIcons = icons
        } else {
            toolbarIcons = [
                ToolbarIcon.toolIcon(.pencil),
                ToolbarIcon.toolIcon(.eraser),
                ToolbarIcon.colorIcon(.black, name: "Black", colorScheme: .light),
                ToolbarIcon.colorIcon(.red, name: "Red", colorScheme: .light),
                ToolbarIcon.colorIcon(.blue, name: "Blue", colorScheme: .light),
                ToolbarIcon.colorIcon(.green, name: "Green", colorScheme: .light),
            ]
        }

        // Ensure pen and eraser always exist
        if !toolbarIcons.contains(where: { $0.type == .pencil }) {
            toolbarIcons.insert(ToolbarIcon.toolIcon(.pencil), at: 0)
        }
        if !toolbarIcons.contains(where: { $0.type == .eraser }) {
            let penIndex = toolbarIcons.firstIndex(where: { $0.type == .pencil }) ?? 0
            toolbarIcons.insert(ToolbarIcon.toolIcon(.eraser), at: penIndex + 1)
        }

        if let data = defaults.data(forKey: Self.selectedColorKey),
           let codable = try? JSONDecoder().decode(CodableColor.self, from: data) {
            selectedColor = codable.toColor()
        }

        if let rawTool = defaults.string(forKey: Self.activeToolKey),
           let tool = ActiveTool(rawValue: rawTool) {
            activeTool = tool
        }
    }

    func save(colorScheme: ColorScheme) {
        let defaults = UserDefaults.standard

        if let data = try? JSONEncoder().encode(toolbarIcons) {
            defaults.set(data, forKey: Self.toolbarIconsKey)
        }

        let codableColor = CodableColor(color: selectedColor, colorScheme: colorScheme)
        if let data = try? JSONEncoder().encode(codableColor) {
            defaults.set(data, forKey: Self.selectedColorKey)
        }

        defaults.set(activeTool.rawValue, forKey: Self.activeToolKey)
    }
}
