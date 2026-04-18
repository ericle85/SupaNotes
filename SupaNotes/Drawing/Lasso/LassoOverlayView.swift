import UIKit
import PencilKit

final class LassoOverlayView: UIView {
    weak var canvasView: PKCanvasView?
    weak var outerScrollView: UIScrollView?

    private enum Mode {
        case idle
        case drawing
        case selected
        case translating
    }

    private var mode: Mode = .idle
    private var lassoPoints: [CGPoint] = []
    private var selectedIndices: [Int] = []
    private var translateStart: CGPoint = .zero
    private var translateCumulative: CGPoint = .zero
    private var drawingBeforeEdit: PKDrawing?

    private let pathLayer = CAShapeLayer()
    private let antsLayer = CAShapeLayer()
    private lazy var editMenuInteraction = UIEditMenuInteraction(delegate: self)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = false

        pathLayer.fillColor = nil
        pathLayer.strokeColor = UIColor.systemBlue.cgColor
        pathLayer.lineWidth = 2
        pathLayer.lineDashPattern = [12, 8]
        pathLayer.lineCap = .round
        pathLayer.lineJoin = .round
        layer.addSublayer(pathLayer)

        antsLayer.fillColor = nil
        antsLayer.strokeColor = UIColor.systemBlue.cgColor
        antsLayer.lineWidth = 2
        antsLayer.lineDashPattern = [12, 8]
        layer.addSublayer(antsLayer)

        addInteraction(editMenuInteraction)
    }

    required init?(coder: NSCoder) { fatalError() }

    func deactivate() {
        clearSelection()
    }

    private func clearSelection() {
        mode = .idle
        lassoPoints = []
        selectedIndices = []
        pathLayer.path = nil
        antsLayer.path = nil
        antsLayer.removeAllAnimations()
        dismissEditMenu()
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, touch.type == .pencil else { return }
        let p = touch.location(in: self)
        switch mode {
        case .idle:
            startLasso(at: p)
        case .selected:
            if let bounds = currentSelectionBounds(), bounds.contains(p) {
                beginTranslate(at: p)
            } else {
                clearSelection()
                startLasso(at: p)
            }
        default:
            break
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let p = touch.location(in: self)
        switch mode {
        case .drawing:
            lassoPoints.append(p)
            updatePathLayer()
        case .translating:
            let dx = p.x - translateStart.x
            let dy = p.y - translateStart.y
            applyTranslation(dx: dx - translateCumulative.x, dy: dy - translateCumulative.y)
            translateCumulative = CGPoint(x: dx, y: dy)
            updateAntsLayer()
        default:
            break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        switch mode {
        case .drawing:
            finishLasso()
        case .translating:
            finishTranslate()
        default:
            break
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    // MARK: - Lasso drawing

    private func startLasso(at p: CGPoint) {
        mode = .drawing
        lassoPoints = [p]
        updatePathLayer()
    }

    private func updatePathLayer() {
        guard let first = lassoPoints.first else {
            pathLayer.path = nil
            return
        }
        let path = UIBezierPath()
        path.move(to: first)
        for pt in lassoPoints.dropFirst() { path.addLine(to: pt) }
        pathLayer.path = path.cgPath
    }

    private func finishLasso() {
        guard let canvasView, lassoPoints.count >= 3 else {
            clearSelection()
            return
        }
        let polygon = lassoPoints
        let indices = LassoHitTest.selectedIndices(in: canvasView.drawing, polygon: polygon)
        pathLayer.path = nil
        lassoPoints = []
        if indices.isEmpty {
            mode = .idle
        } else {
            selectedIndices = indices
            mode = .selected
            updateAntsLayer()
            startAntsAnimation()
            presentEditMenu()
        }
    }

    // MARK: - Selection bounds

    private func currentSelectionStrokes() -> [PKStroke] {
        guard let canvasView else { return [] }
        return selectedIndices.compactMap { idx in
            canvasView.drawing.strokes.indices.contains(idx) ? canvasView.drawing.strokes[idx] : nil
        }
    }

    private func currentSelectionBounds() -> CGRect? {
        LassoHitTest.unionBounds(ofStrokes: currentSelectionStrokes())?.insetBy(dx: -12, dy: -12)
    }

    private func updateAntsLayer() {
        guard let bounds = currentSelectionBounds() else {
            antsLayer.path = nil
            return
        }
        antsLayer.path = UIBezierPath(roundedRect: bounds, cornerRadius: 6).cgPath
    }

    private func startAntsAnimation() {
        let anim = CABasicAnimation(keyPath: "lineDashPhase")
        anim.fromValue = 0
        anim.toValue = 20
        anim.duration = 0.6
        anim.repeatCount = .infinity
        antsLayer.add(anim, forKey: "ants")
    }

    // MARK: - Translate

    private func beginTranslate(at p: CGPoint) {
        guard let canvasView else { return }
        mode = .translating
        translateStart = p
        translateCumulative = .zero
        drawingBeforeEdit = canvasView.drawing
        dismissEditMenu()
    }

    private func applyTranslation(dx: CGFloat, dy: CGFloat) {
        guard let canvasView else { return }
        var drawing = canvasView.drawing
        var strokes = drawing.strokes
        for idx in selectedIndices where strokes.indices.contains(idx) {
            strokes[idx].transform = strokes[idx].transform.concatenating(CGAffineTransform(translationX: dx, y: dy))
        }
        drawing.strokes = strokes
        canvasView.drawing = drawing
    }

    private func finishTranslate() {
        if let canvasView, let before = drawingBeforeEdit {
            registerUndo(before: before, after: canvasView.drawing)
        }
        drawingBeforeEdit = nil
        mode = .selected
        updateAntsLayer()
        presentEditMenu()
    }

    // MARK: - Undo

    private func registerUndo(before: PKDrawing, after: PKDrawing) {
        guard let canvasView else { return }
        canvasView.undoManager?.registerUndo(withTarget: canvasView) { [weak self] cv in
            let redoTarget = cv.drawing
            cv.drawing = before
            self?.clearSelection()
            cv.undoManager?.registerUndo(withTarget: cv) { [weak self] cv2 in
                cv2.drawing = redoTarget
                self?.clearSelection()
            }
        }
    }

    // MARK: - Edit menu

    private func presentEditMenu() {
        guard let bounds = currentSelectionBounds() else { return }
        let source = CGPoint(x: bounds.midX, y: bounds.minY)
        let config = UIEditMenuConfiguration(identifier: nil, sourcePoint: source)
        editMenuInteraction.presentEditMenu(with: config)
    }

    private func dismissEditMenu() {
        editMenuInteraction.dismissMenu()
    }

    // MARK: - Actions

    fileprivate func doCopy() {
        let strokes = currentSelectionStrokes()
        guard !strokes.isEmpty else { return }
        LassoClipboard.data = PKDrawing(strokes: strokes).dataRepresentation()
    }

    fileprivate func doCut() {
        doCopy()
        doDelete()
    }

    fileprivate func doDelete() {
        guard let canvasView else { return }
        let before = canvasView.drawing
        var strokes = canvasView.drawing.strokes
        for idx in selectedIndices.sorted(by: >) where strokes.indices.contains(idx) {
            strokes.remove(at: idx)
        }
        var drawing = canvasView.drawing
        drawing.strokes = strokes
        canvasView.drawing = drawing
        registerUndo(before: before, after: canvasView.drawing)
        clearSelection()
    }

    fileprivate func doDuplicate() {
        guard let canvasView else { return }
        let before = canvasView.drawing
        let offset = CGAffineTransform(translationX: 40, y: 40)
        let copied = currentSelectionStrokes().map { stroke -> PKStroke in
            var s = stroke
            s.transform = s.transform.concatenating(offset)
            return s
        }
        guard !copied.isEmpty else { return }
        var drawing = canvasView.drawing
        let baseCount = drawing.strokes.count
        drawing.strokes.append(contentsOf: copied)
        canvasView.drawing = drawing
        registerUndo(before: before, after: canvasView.drawing)
        selectedIndices = Array(baseCount..<(baseCount + copied.count))
        mode = .selected
        updateAntsLayer()
        startAntsAnimation()
        presentEditMenu()
    }

    fileprivate func doPaste() {
        guard let canvasView, let data = LassoClipboard.data,
              let pasted = try? PKDrawing(data: data), !pasted.strokes.isEmpty else { return }
        let before = canvasView.drawing
        let offset = CGAffineTransform(translationX: 40, y: 40)
        let strokes = pasted.strokes.map { stroke -> PKStroke in
            var s = stroke
            s.transform = s.transform.concatenating(offset)
            return s
        }
        var drawing = canvasView.drawing
        let baseCount = drawing.strokes.count
        drawing.strokes.append(contentsOf: strokes)
        canvasView.drawing = drawing
        registerUndo(before: before, after: canvasView.drawing)
        selectedIndices = Array(baseCount..<(baseCount + strokes.count))
        mode = .selected
        updateAntsLayer()
        startAntsAnimation()
        presentEditMenu()
    }
}

extension LassoOverlayView: UIEditMenuInteractionDelegate {
    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]) -> UIMenu? {
        var items: [UIAction] = [
            UIAction(title: "Cut", image: UIImage(systemName: "scissors")) { [weak self] _ in self?.doCut() },
            UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in self?.doCopy() }
        ]
        if LassoClipboard.data != nil {
            items.append(UIAction(title: "Paste", image: UIImage(systemName: "doc.on.clipboard")) { [weak self] _ in self?.doPaste() })
        }
        items.append(UIAction(title: "Duplicate", image: UIImage(systemName: "plus.square.on.square")) { [weak self] _ in self?.doDuplicate() })
        items.append(UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.doDelete() })
        return UIMenu(children: items)
    }
}
