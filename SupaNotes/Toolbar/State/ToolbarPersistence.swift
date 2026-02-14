import SwiftUI

enum ToolbarPersistence {
    private static let selectedColorKey = "toolbar.selectedColor"
    private static let activeToolKey = "toolbar.activeTool"
    private static let toolbarIconsKey = "toolbar.toolbarIcons"

    static func load(into state: ToolbarState) {
        let defaults = UserDefaults.standard

        if let data = defaults.data(forKey: toolbarIconsKey),
           let icons = try? JSONDecoder().decode([ToolbarIcon].self, from: data),
           !icons.isEmpty {
            state.toolbarIcons = icons
        } else {
            state.toolbarIcons = [
                ToolbarIcon.toolIcon(.pen),
                ToolbarIcon.toolIcon(.eraser),
                ToolbarIcon.colorIcon(.black, name: "Black", colorScheme: .light),
                ToolbarIcon.colorIcon(.red, name: "Red", colorScheme: .light),
                ToolbarIcon.colorIcon(.blue, name: "Blue", colorScheme: .light),
                ToolbarIcon.colorIcon(.green, name: "Green", colorScheme: .light),
            ]
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
    }
}
