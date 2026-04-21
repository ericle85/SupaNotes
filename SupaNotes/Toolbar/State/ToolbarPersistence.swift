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
            ToolbarIcon.colorIcon(.black, name: "Black", colorScheme: colorScheme),
            ToolbarIcon.colorIcon(.red, name: "Red", colorScheme: colorScheme),
            ToolbarIcon.colorIcon(.blue, name: "Blue", colorScheme: colorScheme),
            ToolbarIcon.colorIcon(.green, name: "Green", colorScheme: colorScheme),
        ]
    }

    private static let supportedTools: Set<ToolType> = [.pen, .eraser]

    private static func sanitizedIcons(from icons: [ToolbarIcon], colorScheme: ColorScheme) -> [ToolbarIcon] {
        let filtered = icons.filter { icon in
            icon.type == .color || supportedTools.contains(icon.type)
        }
        return filtered.isEmpty ? defaultIcons(colorScheme: colorScheme) : filtered
    }

    private static func supportedActiveTool(_ tool: ActiveTool) -> ActiveTool {
        switch tool {
        case .pen, .eraser:
            return tool
        case .highlighter, .lasso:
            return .pen
        }
    }

    static func load(into state: ToolbarState) {
        let defaults = UserDefaults.standard

        // 1. Load the icons (tools and colors)
        if let data = defaults.data(forKey: toolbarIconsKey),
           let icons = try? JSONDecoder().decode([ToolbarIcon].self, from: data),
           !icons.isEmpty
        {
            state.toolbarIcons = sanitizedIcons(from: icons, colorScheme: .light)
        } else {
            // If no icons are saved, use the defaults
            state.toolbarIcons = defaultIcons(colorScheme: .light)
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
            state.currentlyActiveTool = supportedActiveTool(tool)
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

    static func save(_ state: ToolbarState, colorScheme: ColorScheme) {
        let defaults = UserDefaults.standard

        // Save the list of icons
        if let data = try? JSONEncoder().encode(state.toolbarIcons) {
            defaults.set(data, forKey: toolbarIconsKey)
        }

        // Save the current color
        let codableColor = CodableColor(color: state.colorSelectedByUser, colorScheme: colorScheme)
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
