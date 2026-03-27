import SwiftUI
import UIKit
import PencilKit

// MARK: - Main View

struct OverlayAccuracyView: View {
    enum Mode: String, CaseIterable {
        case type = "Type"
        case draw = "Draw"
    }

    @State private var mode: Mode = .type
    @State private var overlayText: String = "49"
    @State private var completeness: Double = 0
    @State private var accuracy: Double = 0
    @State private var distanceThreshold: Double = 7

    var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .padding()

            HStack {
                Text("Threshold: \(Int(distanceThreshold))px")
                    .font(.caption.monospaced())
                Slider(value: $distanceThreshold, in: 1...20, step: 1)
            }
            .padding(.horizontal)

            if mode == .type {
                TypeModeView(overlayText: $overlayText)
            } else {
                DrawModeView(
                    overlayText: overlayText,
                    completeness: $completeness,
                    accuracy: $accuracy,
                    distanceThreshold: $distanceThreshold
                )
            }
        }
        .navigationTitle("Overlay Accuracy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Type Mode

private struct TypeModeView: View {
    @Binding var overlayText: String

    var body: some View {
        VStack(spacing: 24) {
            TextField("Overlay text", text: $overlayText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            ZStack {
                Color(.systemBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.3))
                    )

                Text(overlayText)
                    .font(.custom("HelveticaNeue-Bold", size: 40))
                    .foregroundStyle(.gray.opacity(0.35))
            }
            .frame(width: 320, height: 320)

            Spacer()
        }
        .padding(.top, 24)
    }
}

// MARK: - Distance Transform

/// Computes a distance transform on a binary mask using BFS.
/// Each cell stores the Chebyshev distance to the nearest `true` pixel.
private struct DistanceTransform {
    let width: Int
    let height: Int
    /// Flat array [y * width + x] of distances. 0 = target pixel, Int.max = unreachable.
    let distances: [Int]

    /// Number of `true` pixels in the source mask.
    let targetPixelCount: Int

    init(mask: [Bool], width: Int, height: Int) {
        self.width = width
        self.height = height

        var dist = [Int](repeating: Int.max, count: width * height)
        var queue: [(Int, Int)] = []
        var targetCount = 0

        // Seed with all target pixels
        for y in 0 ..< height {
            for x in 0 ..< width {
                let idx = y * width + x
                if mask[idx] {
                    dist[idx] = 0
                    queue.append((x, y))
                    targetCount += 1
                }
            }
        }

        self.targetPixelCount = targetCount

        // BFS with 8-connected neighbors (Chebyshev distance)
        var head = 0
        while head < queue.count {
            let (cx, cy) = queue[head]
            head += 1
            let currentDist = dist[cy * width + cx]

            for dy in -1 ... 1 {
                for dx in -1 ... 1 {
                    if dx == 0 && dy == 0 { continue }
                    let nx = cx + dx
                    let ny = cy + dy
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

// MARK: - Matching Result

private struct MatchResult {
    /// 0–100: percentage of target pixels covered by nearby ink pixels
    let completeness: Double
    /// 0–100: percentage of ink pixels that are near a target pixel (higher = better tracing)
    let accuracy: Double
    /// Per-character completeness (index matches character position in overlay string)
    let perCharCompleteness: [Double]
}

// MARK: - Draw Mode

private struct DrawModeView: UIViewRepresentable {
    let overlayText: String
    @Binding var completeness: Double
    @Binding var accuracy: Double
    @Binding var distanceThreshold: Double

    func makeCoordinator() -> Coordinator {
        Coordinator(overlayText: overlayText, completeness: $completeness, accuracy: $accuracy, distanceThreshold: $distanceThreshold)
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .systemBackground

        // Per-character overlay labels in a horizontal stack
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.tag = 100
        container.addSubview(stack)

        let charLabels = makeCharacterLabels(for: overlayText)
        for label in charLabels {
            stack.addArrangedSubview(label)
        }

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -40),
        ])

        // PencilKit canvas
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .black, width: 5)
        canvas.delegate = context.coordinator
        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.tag = 200
        container.addSubview(canvas)

        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: container.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -80),
        ])

        context.coordinator.canvasView = canvas
        context.coordinator.overlayStack = stack
        context.coordinator.characterLabels = charLabels

        // Status label
        let statusLabel = UILabel()
        statusLabel.text = "Completeness: 0%  Accuracy: 0%"
        statusLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .semibold)
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.tag = 300
        container.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
        ])

        context.coordinator.statusLabel = statusLabel

        // Clear button
        let clearButton = UIButton(type: .system)
        clearButton.setTitle("Clear", for: .normal)
        clearButton.addTarget(
            context.coordinator,
            action: #selector(Coordinator.clearCanvas),
            for: .touchUpInside
        )
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(clearButton)

        NSLayoutConstraint.activate([
            clearButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            clearButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
        ])

        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.overlayText = overlayText
    }

    private func makeCharacterLabels(for text: String) -> [UILabel] {
        text.map { char in
            let label = UILabel()
            label.text = String(char)
            label.font = UIFont(name: "HelveticaNeue-Bold", size: 40) ?? .systemFont(ofSize: 40, weight: .bold)
            label.textColor = UIColor.gray.withAlphaComponent(0.35)
            return label
        }
    }
}

// MARK: - Coordinator

extension DrawModeView {
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var overlayText: String
        @Binding var completeness: Double
        @Binding var accuracy: Double
        @Binding var distanceThreshold: Double

        weak var canvasView: PKCanvasView?
        weak var overlayStack: UIStackView?
        weak var statusLabel: UILabel?
        var characterLabels: [UILabel] = []

        /// Per-character completeness threshold to fade a character.
        private let fadeThreshold: Double = 75.0

        /// Cached distance transform and target mask, rebuilt when overlay layout changes.
        private var cachedTransform: DistanceTransform?
        private var cachedTargetMask: [Bool]?
        private var cachedRenderSize: CGSize = .zero
        private var cachedCharBounds: [CGRect] = []

        init(overlayText: String, completeness: Binding<Double>, accuracy: Binding<Double>, distanceThreshold: Binding<Double>) {
            self.overlayText = overlayText
            _completeness = completeness
            _accuracy = accuracy
            _distanceThreshold = distanceThreshold
        }

        @objc func clearCanvas() {
            canvasView?.drawing = PKDrawing()
            resetOverlay()
        }

        // MARK: PKCanvasViewDelegate

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard let stack = overlayStack, let superview = stack.superview else { return }

            let scale = UIScreen.main.scale
            let stackFrame = stack.frame
            guard stackFrame.width > 0, stackFrame.height > 0 else { return }

            // Build/cache distance transform from overlay labels
            let renderSize = CGSize(
                width: stackFrame.width * scale,
                height: stackFrame.height * scale
            )
            if cachedTransform == nil || cachedRenderSize != renderSize {
                rebuildTransform(stack: stack, scale: scale)
            }

            guard let transform = cachedTransform, let targetMask = cachedTargetMask else { return }

            // Render ink in the overlay region
            let canvasRegion = superview.convert(stackFrame, to: canvasView)
            let inkImage = canvasView.drawing.image(from: canvasRegion, scale: scale)
            guard let inkCG = inkImage.cgImage else { return }

            let w = transform.width
            let h = transform.height

            // Extract ink pixels
            let inkMask = binarize(image: inkCG, width: w, height: h, luminanceThreshold: 128)

            // Compute match
            let result = computeMatch(
                targetMask: targetMask,
                inkMask: inkMask,
                transform: transform,
                charBounds: cachedCharBounds,
                width: w,
                height: h
            )

            DispatchQueue.main.async { [weak self] in
                self?.applyResult(result)
            }
        }

        // MARK: - Transform Building

        private func rebuildTransform(stack: UIStackView, scale: CGFloat) {
            let stackFrame = stack.frame
            let w = Int(stackFrame.width * scale)
            let h = Int(stackFrame.height * scale)
            guard w > 0, h > 0 else { return }

            // Render overlay stack to image
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            let renderer = UIGraphicsImageRenderer(size: stackFrame.size, format: format)
            let overlayImage = renderer.image { ctx in
                stack.layer.render(in: ctx.cgContext)
            }

            guard let overlayCG = overlayImage.cgImage else { return }

            let targetMask = binarize(
                image: overlayCG, width: w, height: h, luminanceThreshold: 200
            )

            // Compute per-character bounding boxes in pixel coordinates
            var charBounds: [CGRect] = []
            for label in characterLabels {
                let labelFrame = label.convert(label.bounds, to: stack)
                charBounds.append(CGRect(
                    x: labelFrame.origin.x * scale,
                    y: labelFrame.origin.y * scale,
                    width: labelFrame.width * scale,
                    height: labelFrame.height * scale
                ))
            }

            cachedTransform = DistanceTransform(mask: targetMask, width: w, height: h)
            cachedTargetMask = targetMask
            cachedRenderSize = CGSize(width: CGFloat(w), height: CGFloat(h))
            cachedCharBounds = charBounds
        }

        // MARK: - Pixel Operations

        /// Binarize a CGImage: pixels with luminance below threshold → true (dark pixel).
        private func binarize(
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
            for i in 0 ..< pixelCount {
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

        // MARK: - Match Computation

        private func computeMatch(
            targetMask: [Bool],
            inkMask: [Bool],
            transform: DistanceTransform,
            charBounds: [CGRect],
            width w: Int,
            height h: Int
        ) -> MatchResult {
            var coveredTargetPixels = 0
            var totalInkPixels = 0
            var onTargetInkPixels = 0

            // Per-character tracking
            var charTargetCounts = [Int](repeating: 0, count: charBounds.count)
            var charCoveredCounts = [Int](repeating: 0, count: charBounds.count)

            let pixelCount = w * h
            let threshold = Int(distanceThreshold)

            // First pass: for each target pixel, check if any ink pixel is nearby.
            // We check the reverse: for each ink pixel, mark nearby target pixels as covered.
            // Using a covered set to avoid double-counting.
            var coveredSet = [Bool](repeating: false, count: pixelCount)

            for i in 0 ..< pixelCount {
                guard inkMask[i] else { continue }
                totalInkPixels += 1

                let ix = i % w
                let iy = i / w

                // Check if this ink pixel is near any target pixel
                let dist = transform.distance(x: ix, y: iy)
                if dist <= threshold {
                    onTargetInkPixels += 1
                }

                // Mark nearby target pixels as covered
                let searchRadius = threshold
                let minX = max(0, ix - searchRadius)
                let maxX = min(w - 1, ix + searchRadius)
                let minY = max(0, iy - searchRadius)
                let maxY = min(h - 1, iy + searchRadius)

                for sy in minY ... maxY {
                    for sx in minX ... maxX {
                        let sIdx = sy * w + sx
                        if targetMask[sIdx] && !coveredSet[sIdx] {
                            coveredSet[sIdx] = true
                            coveredTargetPixels += 1
                        }
                    }
                }
            }

            // Count target pixels per character and how many are covered
            for i in 0 ..< pixelCount {
                guard targetMask[i] else { continue }
                let px = i % w
                let py = i / w

                for (ci, bounds) in charBounds.enumerated() {
                    if CGFloat(px) >= bounds.minX && CGFloat(px) < bounds.maxX
                        && CGFloat(py) >= bounds.minY && CGFloat(py) < bounds.maxY
                    {
                        charTargetCounts[ci] += 1
                        if coveredSet[i] {
                            charCoveredCounts[ci] += 1
                        }
                        break
                    }
                }
            }

            let targetTotal = transform.targetPixelCount
            let overallCompleteness = targetTotal > 0
                ? Double(coveredTargetPixels) / Double(targetTotal) * 100
                : 0
            let overallAccuracy = totalInkPixels > 0
                ? Double(onTargetInkPixels) / Double(totalInkPixels) * 100
                : 0

            let perChar = zip(charTargetCounts, charCoveredCounts).map { total, covered in
                total > 0 ? Double(covered) / Double(total) * 100 : 0
            }

            return MatchResult(
                completeness: overallCompleteness,
                accuracy: overallAccuracy,
                perCharCompleteness: perChar
            )
        }

        // MARK: - Apply Result

        private func applyResult(_ result: MatchResult) {
            completeness = result.completeness
            accuracy = result.accuracy

            statusLabel?.text = String(
                format: "Completeness: %.0f%%  Accuracy: %.0f%%",
                result.completeness, result.accuracy
            )

            // Fade characters that exceed the threshold
            for (i, pct) in result.perCharCompleteness.enumerated() where i < characterLabels.count {
                if pct >= fadeThreshold {
                    UIView.animate(withDuration: 0.3) {
                        self.characterLabels[i].alpha = 0
                    }
                }
            }
        }

        private func resetOverlay() {
            completeness = 0
            accuracy = 0
            statusLabel?.text = "Completeness: 0%  Accuracy: 0%"
            for label in characterLabels {
                label.alpha = 1
            }
            cachedTransform = nil
            cachedTargetMask = nil
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        OverlayAccuracyView()
    }
}
