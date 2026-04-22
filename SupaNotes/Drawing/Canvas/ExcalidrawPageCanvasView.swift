import SwiftUI
import UIKit

// MARK: - Data Format

/// This stores a full page drawing in a simple Codable format.
struct ExcalidrawPageDocument: Codable, Hashable {
    /// Every line the user has drawn on this page.
    var strokes: [ExcalidrawPageStroke] = []
}

/// A single saved line.
struct ExcalidrawPageStroke: Identifiable, Codable, Hashable {
    let id: UUID
    let tool: ExcalidrawPageTool
    let color: ExcalidrawPageColor
    let width: CGFloat
    let points: [ExcalidrawPagePoint]
}

/// Supported tools for this canvas engine.
enum ExcalidrawPageTool: String, Codable {
    case pen
    case highlighter
}

/// Codable color representation.
struct ExcalidrawPageColor: Codable, Hashable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    init(color: Color) {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}

/// Codable point representation.
struct ExcalidrawPagePoint: Codable, Hashable {
    let pointX: CGFloat
    let pointY: CGFloat

    nonisolated init(_ point: CGPoint) {
        pointX = point.x
        pointY = point.y
    }

    var cgPoint: CGPoint {
        CGPoint(x: pointX, y: pointY)
    }
}

/// Encode/decode helper so every page saves with the same format.
enum ExcalidrawPageCodec {
    static func decode(data: Data) -> ExcalidrawPageDocument {
        guard !data.isEmpty else { return ExcalidrawPageDocument() }
        return (try? JSONDecoder().decode(ExcalidrawPageDocument.self, from: data)) ?? ExcalidrawPageDocument()
    }

    static func encode(document: ExcalidrawPageDocument) -> Data {
        (try? JSONEncoder().encode(document)) ?? Data()
    }
}

// MARK: - Tool Style

/// A plain description of the active toolbar settings.
struct ExcalidrawToolStyle {
    let selectedTool: ActiveTool
    let selectedColor: Color
    let penWidth: CGFloat
    let highlighterWidth: CGFloat
    let eraserWidth: CGFloat

    static func from(toolbar: ToolbarState) -> ExcalidrawToolStyle {
        ExcalidrawToolStyle(
            selectedTool: toolbar.currentlyActiveTool,
            selectedColor: toolbar.colorSelectedByUser,
            penWidth: toolbar.instrumentWidth(for: .pen),
            highlighterWidth: toolbar.instrumentWidth(for: .highlighter),
            eraserWidth: toolbar.instrumentWidth(for: .eraser)
        )
    }
}

// MARK: - Interaction Callbacks

/// Lets the parent know when drawing starts/ends on a page.
protocol ExcalidrawPageCanvasInteractionDelegate: AnyObject {
    func pageCanvasViewDidBeginUsingTool(_ view: ExcalidrawPageCanvasView)
    func pageCanvasViewDidEndUsingTool(_ view: ExcalidrawPageCanvasView)
}

/// Tiny target object used for UndoManager callbacks.
private final class ExcalidrawUndoBridge: NSObject {
    var apply: ((ExcalidrawPageDocument) -> Void)?
}

// MARK: - One Page View

/// This view renders exactly one note page.
final class ExcalidrawPageCanvasView: UIView {
    private static let letterSize = CGSize(width: 612, height: 792)

    weak var interactionDelegate: ExcalidrawPageCanvasInteractionDelegate?

    private(set) var page: Page
    private var document = ExcalidrawPageDocument()
    private var activePoints: [CGPoint] = []
    private var erasingIDs = Set<UUID>()
    private var documentBeforeErasing = ExcalidrawPageDocument()

    private let pageUndoManager = UndoManager()
    private let undoBridge = ExcalidrawUndoBridge()

    private var toolStyle: ExcalidrawToolStyle
    private let drawingView = PencilFilteredDrawingUIView()
    private let backgroundImageView = UIImageView()
    private var onPageMutated: () -> Void

    init(page: Page, frame: CGRect, toolStyle: ExcalidrawToolStyle, onPageMutated: @escaping () -> Void) {
        self.page = page
        self.toolStyle = toolStyle
        self.onPageMutated = onPageMutated
        super.init(frame: frame)
        setupUI()
        loadFromPage()
        applyAppearance(for: page)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Exposes the page-specific undo stack so toolbar undo/redo works.
    var undoManagerForPage: UndoManager {
        pageUndoManager
    }

    /// Parent calls this whenever toolbar state changes.
    func updateToolStyle(_ style: ExcalidrawToolStyle) {
        toolStyle = style
    }

    /// Parent can force a save before export/print.
    func flushToModel() {
        persist()
    }

    private func setupUI() {
        clipsToBounds = false

        backgroundImageView.contentMode = .scaleToFill
        backgroundImageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backgroundImageView.frame = bounds
        addSubview(backgroundImageView)

        drawingView.backgroundColor = .clear
        drawingView.translatesAutoresizingMaskIntoConstraints = false
        drawingView.document = document
        drawingView.onGestureBegan = { [weak self] in
            guard let self else { return }
            interactionDelegate?.pageCanvasViewDidBeginUsingTool(self)
        }
        drawingView.onChangedInLetterSpace = { [weak self] point in
            self?.handleChanged(at: point)
        }
        drawingView.onEndedInLetterSpace = { [weak self] point in
            self?.handleEnded(at: point)
            guard let self else { return }
            interactionDelegate?.pageCanvasViewDidEndUsingTool(self)
        }
        addSubview(drawingView)

        NSLayoutConstraint.activate([
            drawingView.topAnchor.constraint(equalTo: topAnchor),
            drawingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            drawingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            drawingView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        undoBridge.apply = { [weak self] restored in
            guard let self else { return }
            document = restored
            drawingView.document = restored
            drawingView.activeStroke = nil
            drawingView.setNeedsDisplay()
            persist()
        }
    }

    private func loadFromPage() {
        document = ExcalidrawPageCodec.decode(data: page.drawingData)
        drawingView.document = document
        drawingView.setNeedsDisplay()
    }

    private func applyAppearance(for page: Page) {
        if let image = PDFService.imageForPage(page) {
            backgroundImageView.image = image
            backgroundImageView.isHidden = false
            backgroundColor = .clear
        } else {
            backgroundImageView.image = nil
            backgroundImageView.isHidden = true
            backgroundColor = page.template.backgroundColor
            overrideUserInterfaceStyle = page.template.interfaceStyle
        }
    }

    private var activeStrokePreview: ExcalidrawPageStroke? {
        guard activePoints.count > 1 else { return nil }
        return ExcalidrawPageStroke(
            id: UUID(),
            tool: activeStrokeTool,
            color: ExcalidrawPageColor(color: toolStyle.selectedColor),
            width: activeLineWidth,
            points: activePoints.map(ExcalidrawPagePoint.init)
        )
    }

    private var activeStrokeTool: ExcalidrawPageTool {
        switch toolStyle.selectedTool {
        case .highlighter: .highlighter
        default: .pen
        }
    }

    private var activeLineWidth: CGFloat {
        switch toolStyle.selectedTool {
        case .highlighter: toolStyle.highlighterWidth
        default: toolStyle.penWidth
        }
    }

    private var eraserWidth: CGFloat {
        toolStyle.eraserWidth
    }

    private func handleChanged(at point: CGPoint) {
        if toolStyle.selectedTool == .eraser {
            handleEraserChanged(at: point)
        } else {
            handleDrawChanged(at: point)
        }
    }

    private func handleEnded(at point: CGPoint) {
        if toolStyle.selectedTool == .eraser {
            handleEraserEnded(at: point)
        } else {
            handleDrawEnded(at: point)
        }
    }

    private func handleDrawChanged(at point: CGPoint) {
        if activePoints.isEmpty {
            activePoints = [point]
            drawingView.activeStroke = activeStrokePreview
            drawingView.setNeedsDisplay()
            return
        }

        guard let last = activePoints.last, distance(last, point) >= 0.5 else { return }
        activePoints.append(point)
        drawingView.activeStroke = activeStrokePreview
        drawingView.setNeedsDisplay()
    }

    private func handleDrawEnded(at point: CGPoint) {
        if activePoints.isEmpty {
            activePoints = [point]
        } else if let last = activePoints.last, distance(last, point) > 0.5 {
            activePoints.append(point)
        }

        defer {
            activePoints = []
            drawingView.activeStroke = nil
            drawingView.setNeedsDisplay()
        }

        guard !activePoints.isEmpty else { return }

        let previous = document
        document.strokes.append(
            ExcalidrawPageStroke(
                id: UUID(),
                tool: activeStrokeTool,
                color: ExcalidrawPageColor(color: toolStyle.selectedColor),
                width: activeLineWidth,
                points: activePoints.map(ExcalidrawPagePoint.init)
            )
        )
        registerUndo(previous: previous, current: document, actionName: "Draw Stroke")
        drawingView.document = document
        persist()
    }

    private func handleEraserChanged(at point: CGPoint) {
        if erasingIDs.isEmpty {
            documentBeforeErasing = document
        }

        let radius = max(eraserWidth, 6)
        let idsToErase = document.strokes
            .filter { !erasingIDs.contains($0.id) && intersects(stroke: $0, point: point, radius: radius) }
            .map(\.id)

        guard !idsToErase.isEmpty else { return }
        erasingIDs.formUnion(idsToErase)
        document.strokes.removeAll { erasingIDs.contains($0.id) }
        drawingView.document = document
        drawingView.setNeedsDisplay()
    }

    private func handleEraserEnded(at point: CGPoint) {
        handleEraserChanged(at: point)
        defer {
            erasingIDs.removeAll()
            documentBeforeErasing = ExcalidrawPageDocument()
        }

        guard documentBeforeErasing != document else { return }
        registerUndo(previous: documentBeforeErasing, current: document, actionName: "Erase Stroke")
        persist()
    }

    private func registerUndo(previous: ExcalidrawPageDocument, current: ExcalidrawPageDocument, actionName: String) {
        pageUndoManager.registerUndo(withTarget: undoBridge) { bridge in
            bridge.apply?(previous)
            self.pageUndoManager.registerUndo(withTarget: bridge) { redoBridge in
                redoBridge.apply?(current)
            }
        }
        pageUndoManager.setActionName(actionName)
    }

    private func persist() {
        page.drawingData = ExcalidrawPageCodec.encode(document: document)
        onPageMutated()
    }

    private func intersects(stroke: ExcalidrawPageStroke, point: CGPoint, radius: CGFloat) -> Bool {
        stroke.points.contains { distance($0.cgPoint, point) <= radius }
    }

    private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}

// MARK: - Pencil-Only Surface

/// Low-level drawing layer that only responds to Apple Pencil input.
private final class PencilFilteredDrawingUIView: UIView {
    private static let letterSize = CGSize(width: 612, height: 792)

    var document = ExcalidrawPageDocument()
    var activeStroke: ExcalidrawPageStroke?
    var onGestureBegan: (() -> Void)?
    var onChangedInLetterSpace: ((CGPoint) -> Void)?
    var onEndedInLetterSpace: ((CGPoint) -> Void)?

    private var activePencilTouch: UITouch?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard bounds.contains(point) else { return nil }
        guard let touches = event?.allTouches else { return self }
        guard !touches.isEmpty else { return self }
        return touches.contains { $0.type == .pencil || $0 == activePencilTouch } ? self : nil
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        context.scaleBy(x: rect.width / Self.letterSize.width, y: rect.height / Self.letterSize.height)

        for stroke in document.strokes {
            drawStroke(stroke, in: context)
        }
        if let activeStroke {
            drawStroke(activeStroke, in: context)
        }
        context.restoreGState()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard activePencilTouch == nil else { return }
        guard let touch = touches.first(where: { $0.type == .pencil }) else { return }

        activePencilTouch = touch
        onGestureBegan?()
        onChangedInLetterSpace?(toLetterSpace(touch.location(in: self)))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard let activePencilTouch else { return }
        guard touches.contains(activePencilTouch) else { return }
        onChangedInLetterSpace?(toLetterSpace(activePencilTouch.location(in: self)))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        guard let activePencilTouch else { return }
        guard touches.contains(activePencilTouch) else { return }
        onEndedInLetterSpace?(toLetterSpace(activePencilTouch.location(in: self)))
        self.activePencilTouch = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        guard let activePencilTouch else { return }
        guard touches.contains(activePencilTouch) else { return }
        onEndedInLetterSpace?(toLetterSpace(activePencilTouch.location(in: self)))
        self.activePencilTouch = nil
    }

    private func toLetterSpace(_ point: CGPoint) -> CGPoint {
        let clampedX = max(0, min(bounds.width, point.x))
        let clampedY = max(0, min(bounds.height, point.y))
        let relativeX = bounds.width > 0 ? clampedX / bounds.width : 0
        let relativeY = bounds.height > 0 ? clampedY / bounds.height : 0
        return CGPoint(x: relativeX * Self.letterSize.width, y: relativeY * Self.letterSize.height)
    }

    private func drawStroke(_ stroke: ExcalidrawPageStroke, in context: CGContext) {
        let points = stroke.points.map(\.cgPoint)
        guard !points.isEmpty else { return }

        let path = UIBezierPath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.lineWidth = stroke.width

        if points.count == 1 {
            let dotRect = CGRect(
                x: points[0].x - stroke.width * 0.5,
                y: points[0].y - stroke.width * 0.5,
                width: stroke.width,
                height: stroke.width
            )
            path.append(UIBezierPath(ovalIn: dotRect))
        } else {
            path.move(to: points[0])
            for index in 1 ..< points.count {
                let previous = points[index - 1]
                let current = points[index]
                let midpoint = CGPoint(x: (previous.x + current.x) * 0.5, y: (previous.y + current.y) * 0.5)
                if index == 1 {
                    path.addLine(to: midpoint)
                } else {
                    path.addQuadCurve(to: midpoint, controlPoint: previous)
                }
                if index == points.count - 1 {
                    path.addQuadCurve(to: current, controlPoint: current)
                }
            }
        }

        let baseColor = UIColor(stroke.color.swiftUIColor)
        let finalColor = stroke.tool == .highlighter ? baseColor.withAlphaComponent(0.35) : baseColor

        context.saveGState()
        context.setBlendMode(stroke.tool == .highlighter ? .multiply : .normal)
        finalColor.setStroke()
        path.stroke()
        context.restoreGState()
    }
}
