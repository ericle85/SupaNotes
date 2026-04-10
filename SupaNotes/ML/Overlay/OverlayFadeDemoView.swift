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
        let fontSize: CGFloat = 40
        let overlayColor = UIColor.gray.withAlphaComponent(0.35)

        // First pass: create views and measure
        var views: [(UIView, FadeTrackable)] = []

        for (type, value) in tokens {
            switch type {
            case .word:
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

                let imgSize = result.size
                imageView.frame = CGRect(x: 0, y: 0, width: imgSize.width, height: imgSize.height)

                var maskLayers: [CAShapeLayer] = []
                for glyph in result.glyphRects {
                    let maskLayer = CAShapeLayer()
                    maskLayer.path = UIBezierPath(rect: glyph.rect).cgPath
                    maskLayer.fillColor = UIColor.white.cgColor
                    maskLayer.opacity = 1.0
                    maskLayers.append(maskLayer)
                }

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

        // Layout views horizontally
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

        var xCursor: CGFloat = 0
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
        canvas.drawingPolicy = .pencilOnly
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
    let glyphRects: [GlyphRect]
    let fadeMaskLayers: [CAShapeLayer]
    var faded: Bool = false
    var fadedGlyphs: Set<Int> = []
}

// MARK: - Element Region (maps trackable + glyph to pixel bounds)

private struct ElementRegion {
    let trackableIndex: Int
    let glyphIndex: Int?   // nil for wordChar
    let pixelBounds: CGRect
    var targetPixelCount: Int = 0
    var isFaded: Bool = false
}

// MARK: - Distance Transform (BFS Chebyshev)

private struct DistanceTransform {
    let width: Int
    let height: Int
    let distances: [Int]
    let targetPixelCount: Int

    init(mask: [Bool], width: Int, height: Int) {
        self.width = width
        self.height = height

        var dist = [Int](repeating: Int.max, count: width * height)
        var queue: [(Int, Int)] = []
        var targetCount = 0

        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                if mask[idx] {
                    dist[idx] = 0
                    queue.append((x, y))
                    targetCount += 1
                }
            }
        }
        self.targetPixelCount = targetCount

        var head = 0
        while head < queue.count {
            let (cx, cy) = queue[head]
            head += 1
            let currentDist = dist[cy * width + cx]
            for dy in -1...1 {
                for dx in -1...1 {
                    if dx == 0 && dy == 0 { continue }
                    let nx = cx + dx, ny = cy + dy
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                    let nIdx = ny * width + nx
                    if dist[nIdx] > currentDist + 1 {
                        dist[nIdx] = currentDist + 1
                        queue.append((nx, ny))
                    }
                }
            }
        }
        self.distances = dist
    }

    func distance(x: Int, y: Int) -> Int {
        guard x >= 0, x < width, y >= 0, y < height else { return Int.max }
        return distances[y * width + x]
    }
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

    // Pixel matching state
    private var cachedTransform: DistanceTransform?
    private var cachedTargetMask: [Bool]?
    private var cachedRenderSize: CGSize = .zero
    private var elementRegions: [ElementRegion] = []
    private var isProcessing = false

    private let fadeThreshold: Double = 65.0
    private let distanceThreshold: Int = 7

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

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    @objc func clearCanvas() {
        canvasView?.drawing = PKDrawing()
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
        // Reset pixel matching cache
        cachedTransform = nil
        cachedTargetMask = nil
        elementRegions = []
        statusLabel?.text = "Draw on the suggestion to fade glyphs"
    }

    // MARK: - PKCanvasViewDelegate

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !isProcessing else { return }
        guard let overlayContainer = overlayContainer else { return }
        guard let stack = overlayContainer.viewWithTag(101) else { return }

        let stackFrame = stack.frame
        guard stackFrame.width > 0, stackFrame.height > 0 else { return }

        // Build/cache distance transform on first call
        let renderScale: CGFloat = 1.0  // 1x for speed
        let renderSize = CGSize(
            width: stackFrame.width * renderScale,
            height: stackFrame.height * renderScale
        )
        if cachedTransform == nil || cachedRenderSize != renderSize {
            rebuildTransform(stack: stack, scale: renderScale)
        }

        guard let transform = cachedTransform, let targetMask = cachedTargetMask else { return }

        isProcessing = true

        // Capture what we need for background work
        let canvasRegion = overlayContainer.convert(stackFrame, to: canvasView)
        let drawing = canvasView.drawing
        let w = transform.width
        let h = transform.height
        let threshold = distanceThreshold
        let fadeThresh = fadeThreshold
        let regions = elementRegions

        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            // Render ink in the overlay region
            let inkImage = drawing.image(from: canvasRegion, scale: renderScale)
            guard let inkCG = inkImage.cgImage else {
                DispatchQueue.main.async { self?.isProcessing = false }
                return
            }

            let inkMask = Self.binarize(image: inkCG, width: w, height: h, luminanceThreshold: 128)

            // Mark target pixels covered by nearby ink
            let pixelCount = w * h
            var coveredSet = [Bool](repeating: false, count: pixelCount)

            for i in 0..<pixelCount where inkMask[i] {
                let ix = i % w, iy = i / w
                let minX = max(0, ix - threshold)
                let maxX = min(w - 1, ix + threshold)
                let minY = max(0, iy - threshold)
                let maxY = min(h - 1, iy + threshold)
                for sy in minY...maxY {
                    for sx in minX...maxX {
                        let sIdx = sy * w + sx
                        if targetMask[sIdx] {
                            coveredSet[sIdx] = true
                        }
                    }
                }
            }

            // Compute per-element completeness
            var elementCoverage: [(index: Int, completeness: Double)] = []
            var totalTarget = 0
            var totalCovered = 0

            for (ei, region) in regions.enumerated() {
                guard !region.isFaded, region.targetPixelCount > 0 else {
                    if region.isFaded { totalTarget += region.targetPixelCount; totalCovered += region.targetPixelCount }
                    continue
                }
                let minX = max(0, Int(region.pixelBounds.minX))
                let maxX = min(w, Int(region.pixelBounds.maxX))
                let minY = max(0, Int(region.pixelBounds.minY))
                let maxY = min(h, Int(region.pixelBounds.maxY))

                var covered = 0
                for y in minY..<maxY {
                    for x in minX..<maxX {
                        let idx = y * w + x
                        if targetMask[idx] && coveredSet[idx] { covered += 1 }
                    }
                }

                let pct = Double(covered) / Double(region.targetPixelCount) * 100
                totalTarget += region.targetPixelCount
                totalCovered += covered
                elementCoverage.append((ei, pct))
            }

            let overallPct = totalTarget > 0 ? Int(Double(totalCovered) / Double(totalTarget) * 100) : 0

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isProcessing = false

                var fadedCount = self.elementRegions.filter(\.isFaded).count

                for (ei, pct) in elementCoverage {
                    guard pct >= fadeThresh, !self.elementRegions[ei].isFaded else { continue }
                    self.elementRegions[ei].isFaded = true
                    fadedCount += 1

                    let region = self.elementRegions[ei]
                    let ti = region.trackableIndex

                    if let gi = region.glyphIndex {
                        // Latex glyph
                        guard !self.trackables[ti].fadedGlyphs.contains(gi) else { continue }
                        self.trackables[ti].fadedGlyphs.insert(gi)
                        let layer = self.trackables[ti].fadeMaskLayers[gi]
                        let anim = CABasicAnimation(keyPath: "opacity")
                        anim.fromValue = 1.0
                        anim.toValue = 0.0
                        anim.duration = 0.25
                        anim.fillMode = .forwards
                        anim.isRemovedOnCompletion = false
                        layer.add(anim, forKey: "fade")
                        layer.opacity = 0
                    } else {
                        // Word char
                        guard !self.trackables[ti].faded else { continue }
                        self.trackables[ti].faded = true
                        UIView.animate(withDuration: 0.3) {
                            self.trackables[ti].view.alpha = 0
                        }
                    }
                }

                let totalElements = self.elementRegions.count
                self.statusLabel?.text = "Faded: \(fadedCount)/\(totalElements) glyphs (\(overallPct)%)"
            }
        }
    }

    // MARK: - Transform Building

    private func rebuildTransform(stack: UIView, scale: CGFloat) {
        let stackFrame = stack.frame
        let w = Int(stackFrame.width * scale)
        let h = Int(stackFrame.height * scale)
        guard w > 0, h > 0 else { return }

        // Render overlay to image
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: stackFrame.size, format: format)
        let overlayImage = renderer.image { ctx in
            stack.layer.render(in: ctx.cgContext)
        }
        guard let overlayCG = overlayImage.cgImage else { return }

        let targetMask = Self.binarize(image: overlayCG, width: w, height: h, luminanceThreshold: 200)

        // Build per-element regions
        var regions: [ElementRegion] = []
        for (ti, trackable) in trackables.enumerated() {
            let viewFrame = trackable.view.frame // in stack coords

            switch trackable.kind {
            case .wordChar:
                let pixelBounds = CGRect(
                    x: viewFrame.origin.x * scale,
                    y: viewFrame.origin.y * scale,
                    width: viewFrame.width * scale,
                    height: viewFrame.height * scale
                )
                var region = ElementRegion(
                    trackableIndex: ti,
                    glyphIndex: nil,
                    pixelBounds: pixelBounds
                )
                region.targetPixelCount = countTargetPixels(
                    in: pixelBounds, targetMask: targetMask, width: w, height: h
                )
                regions.append(region)

            case .latex:
                let viewSize = trackable.view.frame.size
                guard viewSize.width > 0, viewSize.height > 0 else { continue }

                for (gi, glyph) in trackable.glyphRects.enumerated() {
                    let gr = glyph.rect
                    let pixelBounds = CGRect(
                        x: (viewFrame.origin.x + gr.origin.x) * scale,
                        y: (viewFrame.origin.y + gr.origin.y) * scale,
                        width: gr.width * scale,
                        height: gr.height * scale
                    )
                    var region = ElementRegion(
                        trackableIndex: ti,
                        glyphIndex: gi,
                        pixelBounds: pixelBounds
                    )
                    region.targetPixelCount = countTargetPixels(
                        in: pixelBounds, targetMask: targetMask, width: w, height: h
                    )
                    regions.append(region)
                }
            }
        }

        cachedTransform = DistanceTransform(mask: targetMask, width: w, height: h)
        cachedTargetMask = targetMask
        cachedRenderSize = CGSize(width: CGFloat(w), height: CGFloat(h))
        elementRegions = regions
    }

    private func countTargetPixels(
        in bounds: CGRect, targetMask: [Bool], width w: Int, height h: Int
    ) -> Int {
        let minX = max(0, Int(bounds.minX))
        let maxX = min(w, Int(bounds.maxX))
        let minY = max(0, Int(bounds.minY))
        let maxY = min(h, Int(bounds.maxY))
        var count = 0
        for y in minY..<maxY {
            for x in minX..<maxX {
                if targetMask[y * w + x] { count += 1 }
            }
        }
        return count
    }

    // MARK: - Pixel Operations

    private static func binarize(
        image: CGImage, width w: Int, height h: Int, luminanceThreshold: Int
    ) -> [Bool] {
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
