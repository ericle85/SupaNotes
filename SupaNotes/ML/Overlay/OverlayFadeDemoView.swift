import SwiftUI
import UIKit
import PencilKit
import SwiftMath

// MARK: - Main View

struct OverlayFadeDemoView: View {
    @State private var selectedExpression = 0

    private let expressions: [(label: String, tokens: [(OverlayTokenType, String)])] = [
        ("time evolution of ψ", [
            (.word, "the time evolution of "),
            (.latex, "\\psi"),
        ]),
        ("√(x+1) expression", [
            (.word, "equals "),
            (.latex, "\\sqrt{x+1}"),
        ]),
        ("integral", [
            (.latex, "\\int_0^1 f(x)\\,dx"),
        ]),
        ("sum series", [
            (.latex, "\\sum_{n=0}^{\\infty} a_n x^n"),
        ]),
        ("fraction", [
            (.word, "where "),
            (.latex, "\\frac{d}{dx}"),
            (.word, " is the derivative"),
        ]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Picker("Expression", selection: $selectedExpression) {
                ForEach(0..<expressions.count, id: \.self) { i in
                    Text(expressions[i].label).tag(i)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            FadeCanvasView(tokens: expressions[selectedExpression].tokens)
                .id(selectedExpression)
        }
        .navigationTitle("Overlay Fade")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Fade Canvas (UIViewRepresentable)

private struct FadeCanvasView: UIViewRepresentable {
    let tokens: [(OverlayTokenType, String)]

    func makeCoordinator() -> FadeCoordinator {
        FadeCoordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .systemBackground
        container.clipsToBounds = true

        // Zoomable wrapper — contains overlay + canvas, scaled together
        let zoomWrapper = UIView()
        zoomWrapper.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(zoomWrapper)
        NSLayoutConstraint.activate([
            zoomWrapper.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            zoomWrapper.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            zoomWrapper.topAnchor.constraint(equalTo: container.topAnchor),
            zoomWrapper.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -60),
        ])

        // Overlay container — holds word labels and latex image views
        let overlayContainer = UIView()
        overlayContainer.translatesAutoresizingMaskIntoConstraints = false
        overlayContainer.tag = 100
        zoomWrapper.addSubview(overlayContainer)

        // Build overlay content
        let renderer = SwiftMathRenderer()
        var trackables: [FadeTrackable] = []
        var xCursor: CGFloat = 0
        let fontSize: CGFloat = 40
        let overlayColor = UIColor.gray.withAlphaComponent(0.35)

        // First pass: create views and measure
        var views: [(UIView, FadeTrackable)] = []

        for (type, value) in tokens {
            switch type {
            case .word:
                // Per-character labels
                for char in value {
                    let label = UILabel()
                    label.text = String(char)
                    label.font = UIFont(name: "NewYork-Regular", size: fontSize)
                        ?? .systemFont(ofSize: fontSize, weight: .regular)
                    label.textColor = overlayColor
                    label.sizeToFit()
                    let trackable = FadeTrackable(
                        view: label,
                        kind: .wordChar,
                        glyphRects: [],
                        fadeMaskLayers: []
                    )
                    views.append((label, trackable))
                }

            case .latex:
                guard let result = renderer.render(
                    latex: value,
                    fontSize: fontSize,
                    textColor: overlayColor
                ) else { continue }

                let imageView = UIImageView(image: result.image)
                imageView.contentMode = .scaleAspectFit

                // Size image view to match render size
                let imgSize = result.size
                imageView.frame = CGRect(x: 0, y: 0, width: imgSize.width, height: imgSize.height)

                // Create per-glyph fade mask layers
                var maskLayers: [CAShapeLayer] = []
                for glyph in result.glyphRects {
                    let maskLayer = CAShapeLayer()
                    maskLayer.path = UIBezierPath(rect: glyph.rect).cgPath
                    maskLayer.fillColor = UIColor.white.cgColor
                    maskLayer.opacity = 1.0
                    maskLayers.append(maskLayer)
                }

                // Compose a single mask from all glyph layers
                let compositeMask = CALayer()
                compositeMask.frame = CGRect(origin: .zero, size: imgSize)
                for ml in maskLayers {
                    compositeMask.addSublayer(ml)
                }
                imageView.layer.mask = compositeMask

                let trackable = FadeTrackable(
                    view: imageView,
                    kind: .latex(renderResult: result),
                    glyphRects: result.glyphRects,
                    fadeMaskLayers: maskLayers
                )
                views.append((imageView, trackable))
            }
        }

        // Layout views horizontally, vertically centered
        // We'll position after layout pass using constraints
        let stack = UIView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.tag = 101
        overlayContainer.addSubview(stack)

        var totalWidth: CGFloat = 0
        var maxHeight: CGFloat = 0
        for (view, _) in views {
            let size = view.frame.size.width > 0 ? view.frame.size : view.sizeThatFits(CGSize(width: 500, height: 200))
            totalWidth += size.width
            maxHeight = max(maxHeight, size.height)
        }

        // Position each view
        xCursor = 0
        for (view, trackable) in views {
            let size = view.frame.size.width > 0 ? view.frame.size : view.sizeThatFits(CGSize(width: 500, height: 200))
            view.frame = CGRect(
                x: xCursor,
                y: (maxHeight - size.height) / 2,
                width: size.width,
                height: size.height
            )
            stack.addSubview(view)
            trackables.append(trackable)
            xCursor += size.width
        }

        stack.frame = CGRect(x: 0, y: 0, width: totalWidth, height: maxHeight)

        NSLayoutConstraint.activate([
            overlayContainer.centerXAnchor.constraint(equalTo: zoomWrapper.centerXAnchor),
            overlayContainer.centerYAnchor.constraint(equalTo: zoomWrapper.centerYAnchor, constant: -40),
            overlayContainer.widthAnchor.constraint(equalToConstant: totalWidth),
            overlayContainer.heightAnchor.constraint(equalToConstant: maxHeight),
            stack.leadingAnchor.constraint(equalTo: overlayContainer.leadingAnchor),
            stack.topAnchor.constraint(equalTo: overlayContainer.topAnchor),
            stack.widthAnchor.constraint(equalToConstant: totalWidth),
            stack.heightAnchor.constraint(equalToConstant: maxHeight),
        ])

        // PencilKit canvas on top
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .pencilOnly // .anyInput .pencilOnly
        canvas.tool = PKInkingTool(.pen, color: .black, width: 3)
        canvas.delegate = context.coordinator
        canvas.translatesAutoresizingMaskIntoConstraints = false
        zoomWrapper.addSubview(canvas)

        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: zoomWrapper.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: zoomWrapper.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: zoomWrapper.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: zoomWrapper.bottomAnchor),
        ])

        // Status label
        let statusLabel = UILabel()
        statusLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        statusLabel.textAlignment = .center
        statusLabel.text = "Draw on the suggestion to fade glyphs"
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
        ])

        // Clear button
        let clearBtn = UIButton(type: .system)
        clearBtn.setTitle("Clear", for: .normal)
        clearBtn.addTarget(context.coordinator, action: #selector(FadeCoordinator.clearCanvas), for: .touchUpInside)
        clearBtn.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(clearBtn)

        NSLayoutConstraint.activate([
            clearBtn.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            clearBtn.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
        ])

        context.coordinator.canvasView = canvas
        context.coordinator.overlayContainer = overlayContainer
        context.coordinator.trackables = trackables
        context.coordinator.statusLabel = statusLabel
        context.coordinator.zoomWrapper = zoomWrapper

        // Pinch to zoom
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(FadeCoordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator
        canvas.addGestureRecognizer(pinch)

        // Two-finger pan
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(FadeCoordinator.handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.delegate = context.coordinator
        canvas.addGestureRecognizer(pan)

        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - Trackable Element

private enum TrackableKind {
    case wordChar
    case latex(renderResult: SwiftMathRenderResult)
}

private struct FadeTrackable {
    let view: UIView
    let kind: TrackableKind
    let glyphRects: [GlyphRect]      // empty for wordChar
    let fadeMaskLayers: [CAShapeLayer] // empty for wordChar
    var faded: Bool = false            // for wordChar
    var fadedGlyphs: Set<Int> = []     // for latex, indices into glyphRects
}

// MARK: - Coordinator

private final class FadeCoordinator: NSObject, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
    weak var canvasView: PKCanvasView?
    weak var overlayContainer: UIView?
    weak var statusLabel: UILabel?
    weak var zoomWrapper: UIView?
    var trackables: [FadeTrackable] = []

    private var currentScale: CGFloat = 1.0
    private var scaleAtGestureStart: CGFloat = 1.0
    private var currentTranslation: CGPoint = .zero
    private var translationAtGestureStart: CGPoint = .zero

    // MARK: - Zoom / Pan

    @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let wrapper = zoomWrapper else { return }
        switch gesture.state {
        case .began:
            scaleAtGestureStart = currentScale
        case .changed, .ended:
            let newScale = (scaleAtGestureStart * gesture.scale).clamped(to: 0.25...5.0)
            currentScale = newScale
            applyTransform(to: wrapper)
        default: break
        }
    }

    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let wrapper = zoomWrapper else { return }
        switch gesture.state {
        case .began:
            translationAtGestureStart = currentTranslation
        case .changed, .ended:
            let delta = gesture.translation(in: wrapper.superview)
            currentTranslation = CGPoint(
                x: translationAtGestureStart.x + delta.x,
                y: translationAtGestureStart.y + delta.y
            )
            applyTransform(to: wrapper)
        default: break
        }
    }

    private func applyTransform(to view: UIView) {
        view.transform = CGAffineTransform(translationX: currentTranslation.x, y: currentTranslation.y)
            .scaledBy(x: currentScale, y: currentScale)
    }

    // Allow pinch/pan to fire alongside PKCanvasView's recognizers
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        return true
    }

    @objc func clearCanvas() {
        canvasView?.drawing = PKDrawing()
        // Reset zoom/pan
        currentScale = 1.0
        currentTranslation = .zero
        if let wrapper = zoomWrapper {
            UIView.animate(withDuration: 0.3) { self.applyTransform(to: wrapper) }
        }
        for i in trackables.indices {
            switch trackables[i].kind {
            case .wordChar:
                trackables[i].view.alpha = 1
                trackables[i].faded = false
            case .latex:
                for layer in trackables[i].fadeMaskLayers {
                    layer.removeAllAnimations()
                    layer.opacity = 1
                }
                trackables[i].fadedGlyphs = []
            }
        }
        statusLabel?.text = "Draw on the suggestion to fade glyphs"
    }

    // MARK: PKCanvasViewDelegate

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard let overlayContainer = overlayContainer else { return }

        let strokes = canvasView.drawing.strokes
        var totalGlyphs = 0
        var fadedCount = 0

        for i in trackables.indices {
            let trackable = trackables[i]
            let view = trackable.view

            switch trackable.kind {
            case .wordChar:
                totalGlyphs += 1
                if trackable.faded { fadedCount += 1; continue }

                // Check if any stroke intersects this character's frame
                let charRect = overlayContainer.convert(view.frame, to: canvasView)
                if strokesIntersect(strokes, rect: charRect) {
                    trackables[i].faded = true
                    fadedCount += 1
                    UIView.animate(withDuration: 0.65) {
                        view.alpha = 0
                    }
                }

            case .latex(let renderResult):
                let glyphRects = renderResult.glyphRects
                totalGlyphs += glyphRects.count

                // Get the image view's frame in canvas coords
                let viewFrameInCanvas = overlayContainer.convert(view.frame, to: canvasView)
                let viewSize = view.frame.size
                guard viewSize.width > 0, viewSize.height > 0 else { continue }

                for gi in 0..<glyphRects.count {
                    if trackables[i].fadedGlyphs.contains(gi) { fadedCount += 1; continue }

                    // Convert glyph rect (render coords) to canvas coords
                    let gr = glyphRects[gi].rect
                    let canvasRect = CGRect(
                        x: viewFrameInCanvas.origin.x + gr.origin.x * (viewFrameInCanvas.width / viewSize.width),
                        y: viewFrameInCanvas.origin.y + gr.origin.y * (viewFrameInCanvas.height / viewSize.height),
                        width: gr.width * (viewFrameInCanvas.width / viewSize.width),
                        height: gr.height * (viewFrameInCanvas.height / viewSize.height)
                    )

                    if strokesIntersect(strokes, rect: canvasRect) {
                        trackables[i].fadedGlyphs.insert(gi)
                        fadedCount += 1
                        let layer = trackables[i].fadeMaskLayers[gi]
                        let anim = CABasicAnimation(keyPath: "opacity")
                        anim.fromValue = 1.0
                        anim.toValue = 0.0
                        anim.duration = 0.2
                        anim.fillMode = .forwards
                        anim.isRemovedOnCompletion = false
                        layer.add(anim, forKey: "fade")
                        layer.opacity = 0
                    }
                }
            }
        }

        let pct = totalGlyphs > 0 ? Int(Double(fadedCount) / Double(totalGlyphs) * 100) : 0
        statusLabel?.text = "Faded: \(fadedCount)/\(totalGlyphs) glyphs (\(pct)%)"
    }

    /// Check if any stroke's bounding box intersects the given rect
    private func strokesIntersect(_ strokes: [PKStroke], rect: CGRect) -> Bool {
        // Expand rect slightly for tolerance
        let expanded = rect.insetBy(dx: -4, dy: -4)
        for stroke in strokes {
            if stroke.renderBounds.intersects(expanded) {
                // Fine check: see if any control point is inside
                let path = stroke.path
                for j in 0..<path.count {
                    if expanded.contains(path[j].location) {
                        return true
                    }
                }
            }
        }
        return false
    }
}

// MARK: - Helpers

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        OverlayFadeDemoView()
    }
}
