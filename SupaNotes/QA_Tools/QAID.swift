import Foundation

enum QAID {
    static let numbersLink = "nav.numbers"
    static let drawingLink = "nav.drawing"
    static let zoomScrollLink = "nav.zoomScroll"
    static let backButton = "nav.back"

    static let displayedNumber = "displayedNumber"
    static func numberButton(_ n: Int) -> String {
        "numberButton.\(n)"
    }

    static let drawCanvas = "draw.canvas"
    static let strokeCount = "draw.strokeCount"
    static let clearStrokes = "draw.clear"
    static let pencilBridgeCommand = "draw.pencilBridge.command"
    static let pencilBridgeInject = "draw.pencilBridge.inject"
    static let touchType = "draw.touchType"

    static let zoomSurface = "zoom.surface"
    static let zoomScale = "zoom.scale"
    static let panOffset = "zoom.panOffset"
    static let resetTransform = "zoom.reset"
}
