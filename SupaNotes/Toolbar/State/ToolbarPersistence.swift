import SwiftUI

enum ToolbarPersistence {
    private static let selectedColorKey = "toolbar.selectedColor"
    private static let activeToolKey = "toolbar.activeTool"
    private static let toolbarIconsKey = "toolbar.toolbarIcons"
    private static let sectionOrderKey = "toolbar.sectionOrder"
    private static let showUndoRedoKey = "toolbar.showUndoRedo"

    static func defaultIcons() -> [ToolbarIcon] {
        [
            ToolbarIcon.toolIcon(.pen),
            ToolbarIcon.toolIcon(.eraser),
            ToolbarIcon.colorIcon(.black, name: "Black"),
            ToolbarIcon.colorIcon(.red, name: "Red"),
            ToolbarIcon.colorIcon(.blue, name: "Blue"),
            ToolbarIcon.colorIcon(.green, name: "Green"),
        ]
    }

    private static let supportedTools: Set<ToolType> = [.pen, .eraser]

    private static func sanitizedIcons(from icons: [ToolbarIcon]) -> [ToolbarIcon] {
        let filtered = icons.filter { icon in
            icon.type == .color || supportedTools.contains(icon.type)
        }
        return filtered.isEmpty ? defaultIcons() : filtered
    }

    static func load(into state: ToolbarState) {
        let defaults = UserDefaults.standard

        // 1. Load the icons (tools and colors)
        if let data = defaults.data(forKey: toolbarIconsKey),
           let icons = try? JSONDecoder().decode([ToolbarIcon].self, from: data),
           !icons.isEmpty
        {
            state.toolbarIcons = sanitizedIcons(from: icons)
        } else {
            // If no icons are saved, use the defaults
            state.toolbarIcons = defaultIcons()
        }

        // 2. Load the color the user was using
        if let data = defaults.data(forKey: selectedColorKey),
           let codable = try? JSONDecoder().decode(CodableColor.self, from: data)
        {
            state.colorSelectedByUser = codable.toColor()
        }

        // 3. Load the tool the user was using (Pen, Eraser, etc.)
        if let rawTool = defaults.string(forKey: activeToolKey),
           let tool = ActiveTool(rawValue: rawTool)
        {
            state.currentlyActiveTool = tool
        }

        // 4. Load the order of the toolbar sections
        if let data = defaults.data(forKey: sectionOrderKey),
           let order = try? JSONDecoder().decode([ToolbarSection].self, from: data),
           Set(order) == Set(ToolbarSection.allCases)
        {
            state.sectionOrder = order
        }

        // 5. Load whether to show the Undo/Redo buttons
        if defaults.object(forKey: showUndoRedoKey) != nil {
            state.showUndoRedo = defaults.bool(forKey: showUndoRedoKey)
        }
    }

    static func save(_ state: ToolbarState) {
        let defaults = UserDefaults.standard

        // Save the list of icons
        if let data = try? JSONEncoder().encode(state.toolbarIcons) {
            defaults.set(data, forKey: toolbarIconsKey)
        }

        // Save the current color
        let codableColor = CodableColor(color: state.colorSelectedByUser)
        if let data = try? JSONEncoder().encode(codableColor) {
            defaults.set(data, forKey: selectedColorKey)
        }

        // Save the currently active tool
        defaults.set(state.currentlyActiveTool.rawValue, forKey: activeToolKey)

        // Save the order of sections
        if let data = try? JSONEncoder().encode(state.sectionOrder) {
            defaults.set(data, forKey: sectionOrderKey)
        }

        // Save the Undo/Redo visibility
        defaults.set(state.showUndoRedo, forKey: showUndoRedoKey)
    }
}
