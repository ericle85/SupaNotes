import SwiftUI

@Observable
final class ToolbarState {
    var selectedColor: Color = .black
    var penWidth: CGFloat = 3.0
    var eraserWidth: CGFloat = 40.0
    var isErasing: Bool = false
    var toolbarIcons: [ToolbarIcon] = []

    private static let selectedColorKey = "toolbar.selectedColor"
    private static let penWidthKey = "toolbar.penWidth"
    private static let eraserWidthKey = "toolbar.eraserWidth"
    private static let isErasingKey = "toolbar.isErasing"
    private static let toolbarIconsKey = "toolbar.toolbarIcons"

    init() {
        load()
    }

    func load() {
        let defaults = UserDefaults.standard

        if let data = defaults.data(forKey: Self.toolbarIconsKey),
           let icons = try? JSONDecoder().decode([ToolbarIcon].self, from: data),
           !icons.isEmpty {
            toolbarIcons = icons
        } else {
            // First launch defaults — use light scheme for storage
            toolbarIcons = [
                ToolbarIcon.colorIcon(.black, name: "Black", colorScheme: .light),
                ToolbarIcon.colorIcon(.red, name: "Red", colorScheme: .light),
                ToolbarIcon.colorIcon(.blue, name: "Blue", colorScheme: .light),
                ToolbarIcon.colorIcon(.green, name: "Green", colorScheme: .light),
            ]
        }

        if let data = defaults.data(forKey: Self.selectedColorKey),
           let codable = try? JSONDecoder().decode(CodableColor.self, from: data) {
            selectedColor = codable.toColor()
        }

        if let pw = defaults.object(forKey: Self.penWidthKey) as? Double {
            penWidth = CGFloat(pw)
        }
        if let ew = defaults.object(forKey: Self.eraserWidthKey) as? Double {
            eraserWidth = CGFloat(ew)
        }
        if let ie = defaults.object(forKey: Self.isErasingKey) as? Bool {
            isErasing = ie
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

        defaults.set(Double(penWidth), forKey: Self.penWidthKey)
        defaults.set(Double(eraserWidth), forKey: Self.eraserWidthKey)
        defaults.set(isErasing, forKey: Self.isErasingKey)
    }
}
