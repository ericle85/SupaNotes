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

    // MARK: - Persistence keys

    private static let selectedColorKey = "toolbar.selectedColor"
    private static let activeToolKey = "toolbar.activeTool"
    private static let toolbarIconsKey = "toolbar.toolbarIcons"
    private static let sectionOrderKey = "toolbar.sectionOrder"
    private static let showUndoRedoKey = "toolbar.showUndoRedo"
    private static let supportedTools: Set<ToolType> = [.pen, .eraser]

    // MARK: - Computed properties

    /// All toolbar icons that are drawing tools (pen, eraser) — not colors.
    var toolIcons: [ToolbarIcon] {
        toolbarIcons.filter { $0.type != .color }
    }

    /// All toolbar icons that are colors.
    var colorIcons: [ToolbarIcon] {
        toolbarIcons.filter { $0.type == .color }
    }

    // MARK: - Init

    init() {
        loadFromDefaults()
    }

    // MARK: - Actions

    func switchToPreviousTool() {
        let currentTool = currentlyActiveTool
        currentlyActiveTool = toolUsedPreviously
        toolUsedPreviously = currentTool
    }

    func instrumentWidth(for type: ToolType) -> CGFloat {
        let matchingIcon = toolbarIcons.first(where: { icon in icon.type == type })
        return matchingIcon?.instrumentSettings?.width ?? WritingInstrumentSettings.pen().width
    }

    func resetToDefaults() {
        toolbarIcons = Self.defaultIcons()
        sectionOrder = [.undoRedo, .tools, .colors]
        showUndoRedo = true
    }

    // MARK: - Persistence

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

    func save() {
        let defaults = UserDefaults.standard

        if let data = try? JSONEncoder().encode(toolbarIcons) {
            defaults.set(data, forKey: Self.toolbarIconsKey)
        }

        let codableColor = CodableColor(color: colorSelectedByUser)
        if let data = try? JSONEncoder().encode(codableColor) {
            defaults.set(data, forKey: Self.selectedColorKey)
        }

        defaults.set(currentlyActiveTool.rawValue, forKey: Self.activeToolKey)

        if let data = try? JSONEncoder().encode(sectionOrder) {
            defaults.set(data, forKey: Self.sectionOrderKey)
        }

        defaults.set(showUndoRedo, forKey: Self.showUndoRedoKey)
    }

    // MARK: - Private

    private func loadFromDefaults() {
        let defaults = UserDefaults.standard

        if let data = defaults.data(forKey: Self.toolbarIconsKey),
           let icons = try? JSONDecoder().decode([ToolbarIcon].self, from: data),
           !icons.isEmpty
        {
            toolbarIcons = Self.sanitizedIcons(from: icons)
        } else {
            toolbarIcons = Self.defaultIcons()
        }

        if let data = defaults.data(forKey: Self.selectedColorKey),
           let codable = try? JSONDecoder().decode(CodableColor.self, from: data)
        {
            colorSelectedByUser = codable.toColor()
        }

        if let rawTool = defaults.string(forKey: Self.activeToolKey),
           let tool = ActiveTool(rawValue: rawTool)
        {
            currentlyActiveTool = tool
        }

        if let data = defaults.data(forKey: Self.sectionOrderKey),
           let order = try? JSONDecoder().decode([ToolbarSection].self, from: data),
           Set(order) == Set(ToolbarSection.allCases)
        {
            sectionOrder = order
        }

        if defaults.object(forKey: Self.showUndoRedoKey) != nil {
            showUndoRedo = defaults.bool(forKey: Self.showUndoRedoKey)
        }
    }

    private static func sanitizedIcons(from icons: [ToolbarIcon]) -> [ToolbarIcon] {
        let filtered = icons.filter { icon in
            icon.type == .color || supportedTools.contains(icon.type)
        }
        return filtered.isEmpty ? defaultIcons() : filtered
    }
}
