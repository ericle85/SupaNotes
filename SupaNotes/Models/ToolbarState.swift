import SwiftUI

enum ActiveTool: String, Codable, Equatable {
    case pen, eraser, highlighter, lasso, text
}

@Observable
final class ToolbarState {
    var selectedColor: Color = .black
    var activeTool: ActiveTool = .pen
    var toolbarIcons: [ToolbarIcon] = []

    private static let selectedColorKey = "toolbar.selectedColor"
    private static let activeToolKey = "toolbar.activeTool"
    private static let isErasingKey = "toolbar.isErasing" // backward compat
    private static let toolbarIconsKey = "toolbar.toolbarIcons"

    // Legacy keys for backward compat migration
    private static let penWidthKey = "toolbar.penWidth"
    private static let eraserWidthKey = "toolbar.eraserWidth"
    private static let highlighterWidthKey = "toolbar.highlighterWidth"
    private static let penPresetsKey = "toolbar.penPresets"

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
            // First launch defaults
            toolbarIcons = [
                ToolbarIcon.toolIcon(.pencil),
                ToolbarIcon.toolIcon(.eraser),
                ToolbarIcon.colorIcon(.black, name: "Black", colorScheme: .light),
                ToolbarIcon.colorIcon(.red, name: "Red", colorScheme: .light),
                ToolbarIcon.colorIcon(.blue, name: "Blue", colorScheme: .light),
                ToolbarIcon.colorIcon(.green, name: "Green", colorScheme: .light),
            ]
        }

        // Backward compat: migrate old pen/eraser/highlighter width keys into instrumentSettings
        if let pw = defaults.object(forKey: Self.penWidthKey) as? Double {
            if let idx = toolbarIcons.firstIndex(where: { $0.type == .pencil }) {
                toolbarIcons[idx].instrumentSettings?.width = CGFloat(pw)
            }
            defaults.removeObject(forKey: Self.penWidthKey)
        }
        if let ew = defaults.object(forKey: Self.eraserWidthKey) as? Double {
            if let idx = toolbarIcons.firstIndex(where: { $0.type == .eraser }) {
                toolbarIcons[idx].instrumentSettings?.width = CGFloat(ew)
            }
            defaults.removeObject(forKey: Self.eraserWidthKey)
        }
        if let hw = defaults.object(forKey: Self.highlighterWidthKey) as? Double {
            if let idx = toolbarIcons.firstIndex(where: { $0.type == .highlighter }) {
                toolbarIcons[idx].instrumentSettings?.width = CGFloat(hw)
            }
            defaults.removeObject(forKey: Self.highlighterWidthKey)
        }
        if let data = defaults.data(forKey: Self.penPresetsKey),
           let presets = try? JSONDecoder().decode([CGFloat].self, from: data),
           presets.count == 3 {
            if let idx = toolbarIcons.firstIndex(where: { $0.type == .pencil }) {
                toolbarIcons[idx].instrumentSettings?.presets = presets
            }
            defaults.removeObject(forKey: Self.penPresetsKey)
        }

        // Ensure pen and eraser always exist (essential tools)
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

        // Load activeTool with backward compat for old isErasing key
        if let rawTool = defaults.string(forKey: Self.activeToolKey),
           let tool = ActiveTool(rawValue: rawTool) {
            activeTool = tool
        } else if let isErasing = defaults.object(forKey: Self.isErasingKey) as? Bool {
            activeTool = isErasing ? .eraser : .pen
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
