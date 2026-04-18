import SwiftUI

enum ToolbarPersistence {
    private static let selectedColorKey = "toolbar.selectedColor"
    private static let activeToolKey = "toolbar.activeTool"
    private static let toolbarIconsKey = "toolbar.toolbarIcons"
    private static let sectionOrderKey = "toolbar.sectionOrder"
    private static let showUndoRedoKey = "toolbar.showUndoRedo"

    static func defaultIcons(colorScheme: ColorScheme) -> [ToolbarIcon] {
        [
            ToolbarIcon.toolIcon(.pen),
            ToolbarIcon.toolIcon(.eraser),
            ToolbarIcon.toolIcon(.highlighter),
            ToolbarIcon.toolIcon(.lasso),
            ToolbarIcon.colorIcon(.black, name: "Black", colorScheme: colorScheme),
            ToolbarIcon.colorIcon(.red, name: "Red", colorScheme: colorScheme),
            ToolbarIcon.colorIcon(.blue, name: "Blue", colorScheme: colorScheme),
            ToolbarIcon.colorIcon(.green, name: "Green", colorScheme: colorScheme),
        ]
    }

    static func load(into state: ToolbarState) {
        let defaults = UserDefaults.standard

        if let data = defaults.data(forKey: toolbarIconsKey),
           let icons = try? JSONDecoder().decode([ToolbarIcon].self, from: data),
           !icons.isEmpty {
            state.toolbarIcons = icons
        } else {
            state.toolbarIcons = defaultIcons(colorScheme: .light)
        }

        // Ensure pen and eraser always exist
        if !state.toolbarIcons.contains(where: { $0.type == .pen }) {
            state.toolbarIcons.insert(ToolbarIcon.toolIcon(.pen), at: 0)
        }
        if !state.toolbarIcons.contains(where: { $0.type == .eraser }) {
            let penIndex = state.toolbarIcons.firstIndex(where: { $0.type == .pen }) ?? 0
            state.toolbarIcons.insert(ToolbarIcon.toolIcon(.eraser), at: penIndex + 1)
        }

        if let data = defaults.data(forKey: selectedColorKey),
           let codable = try? JSONDecoder().decode(CodableColor.self, from: data) {
            state.selectedColor = codable.toColor()
        }

        if let rawTool = defaults.string(forKey: activeToolKey),
           let tool = ActiveTool(rawValue: rawTool) {
            state.activeTool = tool
        }

        if let data = defaults.data(forKey: sectionOrderKey),
           let order = try? JSONDecoder().decode([ToolbarSection].self, from: data),
           Set(order) == Set(ToolbarSection.allCases) {
            state.sectionOrder = order
        }

        if defaults.object(forKey: showUndoRedoKey) != nil {
            state.showUndoRedo = defaults.bool(forKey: showUndoRedoKey)
        }
    }

    static func save(_ state: ToolbarState, colorScheme: ColorScheme) {
        let defaults = UserDefaults.standard

        if let data = try? JSONEncoder().encode(state.toolbarIcons) {
            defaults.set(data, forKey: toolbarIconsKey)
        }

        let codableColor = CodableColor(color: state.selectedColor, colorScheme: colorScheme)
        if let data = try? JSONEncoder().encode(codableColor) {
            defaults.set(data, forKey: selectedColorKey)
        }

        defaults.set(state.activeTool.rawValue, forKey: activeToolKey)

        if let data = try? JSONEncoder().encode(state.sectionOrder) {
            defaults.set(data, forKey: sectionOrderKey)
        }
        defaults.set(state.showUndoRedo, forKey: showUndoRedoKey)
    }
}
