import SwiftUI
import UIKit

// MARK: - Pencil-only drawing surface

private struct PencilCanvasView: UIViewRepresentable {
    @Binding var strokes: [[(CGPoint, TimeInterval)]]
    @Binding var currentStroke: [(CGPoint, TimeInterval)]
    @Binding var t0: TimeInterval

    func makeUIView(context: Context) -> PencilDrawingView {
        let view = PencilDrawingView()
        view.delegate = context.coordinator
        view.backgroundColor = UIColor(white: 0.08, alpha: 1)
        return view
    }

    func updateUIView(_ uiView: PencilDrawingView, context: Context) {
        uiView.allStrokes = strokes
        uiView.currentStroke = currentStroke
        uiView.setNeedsDisplay()
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PencilDrawingDelegate {
        let parent: PencilCanvasView
        init(_ parent: PencilCanvasView) { self.parent = parent }

        func strokeBegan(at point: CGPoint, time: TimeInterval) {
            if parent.currentStroke.isEmpty && parent.strokes.isEmpty {
                parent.t0 = Date.timeIntervalSinceReferenceDate
            }
            let t = Date.timeIntervalSinceReferenceDate - parent.t0
            parent.currentStroke = [(point, t)]
        }
        func strokeMoved(to point: CGPoint, time: TimeInterval) {
            let t = Date.timeIntervalSinceReferenceDate - parent.t0
            parent.currentStroke.append((point, t))
        }
        func strokeEnded() {
            if parent.currentStroke.count >= 2 {
                parent.strokes.append(parent.currentStroke)
            }
            parent.currentStroke = []
        }
    }
}

private protocol PencilDrawingDelegate: AnyObject {
    func strokeBegan(at point: CGPoint, time: TimeInterval)
    func strokeMoved(to point: CGPoint, time: TimeInterval)
    func strokeEnded()
}

private class PencilDrawingView: UIView {
    weak var delegate: PencilDrawingDelegate?
    var allStrokes: [[(CGPoint, TimeInterval)]] = []
    var currentStroke: [(CGPoint, TimeInterval)] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
    }
    required init?(coder: NSCoder) { fatalError() }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, touch.type == .pencil else { return }
        delegate?.strokeBegan(at: touch.location(in: self), time: touch.timestamp)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, touch.type == .pencil else { return }
        delegate?.strokeMoved(to: touch.location(in: self), time: touch.timestamp)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, touch.type == .pencil else { return }
        delegate?.strokeEnded()
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        delegate?.strokeEnded()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.setStrokeColor(UIColor.cyan.cgColor)
        ctx.setLineWidth(2.5)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for stroke in allStrokes { drawStroke(stroke, in: ctx) }
        drawStroke(currentStroke, in: ctx)
    }

    private func drawStroke(_ stroke: [(CGPoint, TimeInterval)], in ctx: CGContext) {
        guard stroke.count >= 2 else { return }
        ctx.beginPath()
        ctx.move(to: stroke[0].0)
        for i in 1..<stroke.count { ctx.addLine(to: stroke[i].0) }
        ctx.strokePath()
    }
}

// MARK: - Demo View

struct HWRDemoView: View {
    @State private var strokes: [[(CGPoint, TimeInterval)]] = []
    @State private var currentStroke: [(CGPoint, TimeInterval)] = []
    @State private var result: DecodeResult?
    @State private var threshold: Float = 0.7
    @State private var seqLen = 0
    @State private var isLoading = false
    @State private var model: CTCModel?
    @State private var errorMessage: String?
    @State private var t0: TimeInterval = 0

    var body: some View {
        VStack(spacing: 0) {
            PencilCanvasView(
                strokes: $strokes,
                currentStroke: $currentStroke,
                t0: $t0
            )
            .frame(maxWidth: .infinity)
            .frame(height: 400)
            .cornerRadius(12)
            .padding(.horizontal)
            .padding(.top)

            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        Button("Clear") {
                            strokes = []; currentStroke = []; result = nil; seqLen = 0
                        }
                        .buttonStyle(.borderedProminent).tint(.red)

                        Button(isLoading ? "..." : "Predict") { predict() }
                            .buttonStyle(.borderedProminent).tint(.green)
                            .disabled(strokes.isEmpty || isLoading)
                    }

                    HStack {
                        Text("Threshold: \(threshold, specifier: "%.2f")")
                            .font(.caption).monospacedDigit()
                        Slider(value: $threshold, in: 0.01...0.99, step: 0.01)
                            .frame(width: 200)
                    }

                    if let r = result {
                        HStack(spacing: 16) {
                            resultBox(title: "Raw", text: r.raw)
                            resultBox(title: "Thresholded", tokens: r.tokens)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(Array(r.tokens.enumerated()), id: \.offset) { _, tok in
                                    VStack(spacing: 2) {
                                        Text(tok.confidence < threshold ? "?" : tok.token)
                                            .font(.caption)
                                        Text(String(format: "%.2f", tok.confidence))
                                            .font(.system(size: 9))
                                    }
                                    .padding(4)
                                    .background(tok.confidence < threshold
                                                ? Color.red.opacity(0.3)
                                                : Color.green.opacity(0.2))
                                    .cornerRadius(4)
                                }
                            }
                        }

                        Text("Seq len: \(seqLen)")
                            .font(.caption).foregroundColor(.secondary)
                    }

                    if let err = errorMessage {
                        Text(err).foregroundColor(.red).font(.caption)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal)
            }
        }
        .navigationTitle("HWR Demo")
        .onAppear {
            guard model == nil else { return }
            do { model = try CTCModel() }
            catch { errorMessage = "Model load: \(error.localizedDescription)" }
        }
    }

    // MARK: - Helpers

    private func resultBox(title: String, text: String) -> some View {
        VStack {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(text).font(.title2).monospaced().textSelection(.enabled)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(white: 0.08))
        .cornerRadius(8)
    }

    private func resultBox(title: String, tokens: [TokenDetail]) -> some View {
        VStack {
            Text(title).font(.caption).foregroundColor(.secondary)
            thresholdedText(tokens).font(.title2).monospaced().textSelection(.enabled)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(white: 0.05, opacity: 0.8))
        .cornerRadius(8)
    }

    private func thresholdedText(_ tokens: [TokenDetail]) -> Text {
        var result = Text("")
        for tok in tokens {
            if tok.confidence < threshold {
                result = result + Text("?").foregroundColor(.red).bold()
            } else {
                result = result + Text(tok.token)
            }
        }
        return result
    }

    // MARK: - Actions

    private func toStrokePoints() -> [[StrokePoint]] {
        strokes.map { stroke in
            stroke.map { StrokePoint(x: Float($0.0.x), y: Float($0.0.y), t: Float($0.1)) }
        }
    }

    private func predict() {
        guard let model else { return }
        isLoading = true

        let strokePoints = toStrokePoints()
        let normalized = normalizeStrokes(strokePoints)
        let features = extractPointFeatures(normalized)
        let nPoints = features.count / FEATURE_DIM
        seqLen = nPoints

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let r = try model.predict(features: features, seqLen: nPoints, threshold: threshold)
                DispatchQueue.main.async { result = r; isLoading = false }
            } catch {
                DispatchQueue.main.async {
                    errorMessage = "Predict: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
}
