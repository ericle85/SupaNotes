import XCTest

extension XCUIElement {

    func draw(from start: CGVector, to end: CGVector, duration: TimeInterval = 0.4) {
        let a = coordinate(withNormalizedOffset: start)
        let b = coordinate(withNormalizedOffset: end)
        a.press(forDuration: duration, thenDragTo: b)
    }

    func draw(path points: [CGVector], duration: TimeInterval = 0.1) {
        guard points.count >= 2 else { return }
        coordinate(withNormalizedOffset: points[0])
            .press(forDuration: duration,
                   thenDragTo: coordinate(withNormalizedOffset: points[1]))
        var previous = points[1]
        for point in points.dropFirst(2) {
            coordinate(withNormalizedOffset: previous)
                .press(forDuration: duration,
                       thenDragTo: coordinate(withNormalizedOffset: point))
            previous = point
        }
    }

    func pinchToZoom(scale: CGFloat, velocity: CGFloat = 1.0) {
        pinch(withScale: scale, velocity: scale >= 1 ? abs(velocity) : -abs(velocity))
    }

    func pan(from start: CGVector, to end: CGVector) {
        coordinate(withNormalizedOffset: start)
            .press(forDuration: 0.1, thenDragTo: coordinate(withNormalizedOffset: end))
    }
}

extension XCUIApplication {
    func text(_ identifier: String, timeout: TimeInterval = 5) -> String {
        let element = staticTexts[identifier]
        _ = element.waitForExistence(timeout: timeout)
        return element.label
    }

    func injectPencilStroke(_ points: [CGVector] = []) {
        if !points.isEmpty {
            let field = textFields[QAID.pencilBridgeCommand]
            field.tap()
            field.typeText(points.map { "\($0.dx),\($0.dy)" }.joined(separator: " "))
        }
        buttons[QAID.pencilBridgeInject].tap()
    }
}
