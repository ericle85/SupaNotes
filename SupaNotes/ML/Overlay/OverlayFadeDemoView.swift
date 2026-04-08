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

        // Overlay container — holds word labels and latex image views
        let overlayContainer = UIView()
        overlayContainer.translatesAutoresizingMaskIntoConstraints = false
        overlayContainer.tag = 100
        container.addSubview(overlayContainer)

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
            overlayContainer.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            overlayContainer.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -40),
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
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .black, width: 3)
        canvas.delegate = context.coordinator
        canvas.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(canvas)

        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: container.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -60),
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
    /// Cached per-glyph target masks (pixels belonging to this glyph, excluding children)
    var perGlyphMasks: [[Bool]] = []
    var cachedMaskSize: (Int, Int) = (0, 0)
}

// MARK: - Coordinator

private final class FadeCoordinator: NSObject, PKCanvasViewDelegate {
    weak var canvasView: PKCanvasView?
    weak var overlayContainer: UIView?
    weak var statusLabel: UILabel?
    var trackables: [FadeTrackable] = []

    private let fadeThreshold: Double = 40.0
    private let distanceThreshold: Int = 12

    @objc func clearCanvas() {
        canvasView?.drawing = PKDrawing()
        // Reset all fades
        for i in trackables.indices {
            switch trackables[i].kind {
            case .wordChar:
                trackables[i].view.alpha = 1
                trackables[i].faded = false
            case .latex:
                for layer in trackables[i].fadeMaskLayers {
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

        let scale = UIScreen.main.scale
        var totalGlyphs = 0
        var fadedCount = 0

        for i in trackables.indices {
            let trackable = trackables[i]
            let view = trackable.view

            // Get view frame in canvas coordinates
            let frameInCanvas = overlayContainer.convert(view.frame, to: canvasView)
            guard frameInCanvas.width > 1, frameInCanvas.height > 1 else { continue }

            // Render ink in this view's region
            let inkImage = canvasView.drawing.image(from: frameInCanvas, scale: scale)
            guard let inkCG = inkImage.cgImage else { continue }

            let w = Int(frameInCanvas.width * scale)
            let h = Int(frameInCanvas.height * scale)
            guard w > 0, h > 0 else { continue }

            let inkMask = binarize(image: inkCG, width: w, height: h, luminanceThreshold: 128)

            switch trackable.kind {
            case .wordChar:
                totalGlyphs += 1
                if trackable.faded {
                    fadedCount += 1
                    continue
                }

                // Render the label to get target mask
                let targetMask = renderViewMask(view: view, width: w, height: h, scale: scale)
                let completeness = computeCompleteness(
                    targetMask: targetMask, inkMask: inkMask, width: w, height: h
                )
                if completeness >= fadeThreshold {
                    trackables[i].faded = true
                    fadedCount += 1
                    UIView.animate(withDuration: 0.3) {
                        view.alpha = 0
                    }
                }

            case .latex(let renderResult):
                let glyphRects = renderResult.glyphRects
                totalGlyphs += glyphRects.count

                // Build per-glyph target masks if not cached
                if trackables[i].perGlyphMasks.isEmpty || trackables[i].cachedMaskSize != (w, h) {
                    trackables[i].perGlyphMasks = buildPerGlyphMasks(
                        view: view, renderResult: renderResult,
                        width: w, height: h, scale: scale
                    )
                    trackables[i].cachedMaskSize = (w, h)
                }

                let perGlyphMasks = trackables[i].perGlyphMasks

                for gi in 0..<glyphRects.count {
                    if trackables[i].fadedGlyphs.contains(gi) {
                        fadedCount += 1
                        continue
                    }

                    guard gi < perGlyphMasks.count else { continue }
                    let glyphMask = perGlyphMasks[gi]

                    let completeness = computeCompleteness(
                        targetMask: glyphMask, inkMask: inkMask, width: w, height: h
                    )

                    if completeness >= fadeThreshold {
                        trackables[i].fadedGlyphs.insert(gi)
                        fadedCount += 1
                        let layer = trackables[i].fadeMaskLayers[gi]
                        let anim = CABasicAnimation(keyPath: "opacity")
                        anim.fromValue = 1.0
                        anim.toValue = 0.0
                        anim.duration = 0.3
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

    // MARK: - Pixel Helpers

    private func binarize(image: CGImage, width w: Int, height h: Int, luminanceThreshold: Int) -> [Bool] {
        let pixelCount = w * h
        var pixels = [UInt8](repeating: 0, count: pixelCount * 4)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let ctx = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: colorSpace, bitmapInfo: bitmapInfo
        ) else {
            return [Bool](repeating: false, count: pixelCount)
        }

        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        var mask = [Bool](repeating: false, count: pixelCount)
        for i in 0..<pixelCount {
            let base = i * 4
            let alpha = pixels[base + 3]
            guard alpha > 10 else { continue }
            let r = Int(pixels[base])
            let g = Int(pixels[base + 1])
            let b = Int(pixels[base + 2])
            let lum = (r + g + b) / 3
            mask[i] = lum < luminanceThreshold
        }
        return mask
    }

    private func renderViewMask(view: UIView, width w: Int, height h: Int, scale: CGFloat) -> [Bool] {
        let size = view.bounds.size
        guard size.width > 0, size.height > 0 else {
            return [Bool](repeating: false, count: w * h)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { ctx in
            view.layer.render(in: ctx.cgContext)
        }
        guard let cg = image.cgImage else {
            return [Bool](repeating: false, count: w * h)
        }
        return binarize(image: cg, width: w, height: h, luminanceThreshold: 200)
    }

    /// Completeness for a single word character (whole view region)
    private func computeCompleteness(
        targetMask: [Bool], inkMask: [Bool], width w: Int, height h: Int
    ) -> Double {
        var targetCount = 0
        var coveredCount = 0
        let threshold = distanceThreshold

        // Build covered set from ink
        var coveredSet = [Bool](repeating: false, count: w * h)

        for i in 0..<(w * h) {
            guard inkMask[i] else { continue }
            let ix = i % w
            let iy = i / w
            let minX = max(0, ix - threshold)
            let maxX = min(w - 1, ix + threshold)
            let minY = max(0, iy - threshold)
            let maxY = min(h - 1, iy + threshold)
            for sy in minY...maxY {
                for sx in minX...maxX {
                    let sIdx = sy * w + sx
                    if targetMask[sIdx] && !coveredSet[sIdx] {
                        coveredSet[sIdx] = true
                    }
                }
            }
        }

        for i in 0..<(w * h) {
            if targetMask[i] {
                targetCount += 1
                if coveredSet[i] { coveredCount += 1 }
            }
        }

        return targetCount > 0 ? Double(coveredCount) / Double(targetCount) * 100 : 0
    }

    /// Build per-glyph target masks from the rendered LaTeX image.
    /// Each mask contains only the pixels belonging to that glyph's rect,
    /// excluding pixels that fall within any strictly-smaller child glyph rect.
    /// This way container symbols (√, ∑, ∫) only track their own drawn pixels.
    private func buildPerGlyphMasks(
        view: UIView, renderResult: SwiftMathRenderResult,
        width w: Int, height h: Int, scale: CGFloat
    ) -> [[Bool]] {
        // Render the full latex image view to get the target pixel mask
        let fullMask = renderViewMask(view: view, width: w, height: h, scale: scale)

        let viewSize = view.frame.size
        guard viewSize.width > 0, viewSize.height > 0 else {
            return Array(repeating: [Bool](repeating: false, count: w * h), count: renderResult.glyphRects.count)
        }

        let scaleX = CGFloat(w) / viewSize.width
        let scaleY = CGFloat(h) / viewSize.height

        // Convert all glyph rects to pixel coords
        let pixelRects = renderResult.glyphRects.map { glyph -> CGRect in
            CGRect(
                x: glyph.rect.origin.x * scaleX,
                y: glyph.rect.origin.y * scaleY,
                width: glyph.rect.width * scaleX,
                height: glyph.rect.height * scaleY
            )
        }

        // For each glyph, find child rects (strictly smaller rects contained within it)
        var childRectIndices: [[Int]] = Array(repeating: [], count: pixelRects.count)
        for gi in 0..<pixelRects.count {
            let parentRect = pixelRects[gi]
            for ci in 0..<pixelRects.count {
                guard ci != gi else { continue }
                let childRect = pixelRects[ci]
                // A child is strictly smaller and contained within the parent
                let childArea = childRect.width * childRect.height
                let parentArea = parentRect.width * parentRect.height
                if parentRect.contains(childRect) && childArea < parentArea * 0.95 {
                    childRectIndices[gi].append(ci)
                }
            }
        }

        // Build per-glyph masks
        var masks: [[Bool]] = []
        for gi in 0..<pixelRects.count {
            let rect = pixelRects[gi]
            let rMinX = max(0, Int(rect.minX))
            let rMaxX = min(w - 1, Int(rect.maxX))
            let rMinY = max(0, Int(rect.minY))
            let rMaxY = min(h - 1, Int(rect.maxY))

            var mask = [Bool](repeating: false, count: w * h)

            guard rMaxX > rMinX, rMaxY > rMinY else {
                masks.append(mask)
                continue
            }

            for y in rMinY...rMaxY {
                for x in rMinX...rMaxX {
                    let idx = y * w + x
                    guard fullMask[idx] else { continue }

                    // Exclude pixels inside child rects
                    let pt = CGPoint(x: CGFloat(x), y: CGFloat(y))
                    var inChild = false
                    for ci in childRectIndices[gi] {
                        if pixelRects[ci].contains(pt) {
                            inChild = true
                            break
                        }
                    }
                    if !inChild {
                        mask[idx] = true
                    }
                }
            }

            masks.append(mask)
        }

        return masks
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        OverlayFadeDemoView()
    }
}
