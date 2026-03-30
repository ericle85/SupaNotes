import SwiftUI
import Vision
import PencilKit
import UIKit

struct VisionBenchmarkView: View {
    @State private var canvasView = PKCanvasView()
    @State private var hasDrawing = false
    @State private var results: [BenchmarkResult] = []
    @State private var recognizedText: String = ""
    @State private var isRunning = false
    @State private var iterations = 50
    @State private var debugImage: UIImage?
    @State private var showDebugImage = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Draw a single digit, then benchmark Vision OCR inference speed vs your CTC model (15ms baseline).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                ZStack {
                    Color.white
                    CanvasRepresentable(canvasView: $canvasView, hasDrawing: $hasDrawing)
                }
                .frame(width: 150, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.4)))

                if !recognizedText.isEmpty {
                    HStack {
                        Text("Vision output:")
                            .foregroundStyle(.secondary)
                        Text(recognizedText.isEmpty ? "(nothing)" : recognizedText)
                            .bold()
                            .foregroundStyle(recognizedText == "(nothing)" ? .red : .primary)
                        Spacer()
                    }
                    .padding(.horizontal)
                }

                HStack {
                    Button("Clear") {
                        canvasView.drawing = PKDrawing()
                        hasDrawing = false
                        results = []
                        recognizedText = ""
                    }
                    .buttonStyle(.bordered)

                    Stepper("Runs: \(iterations)", value: $iterations, in: 10...200, step: 10)

                    Button(isRunning ? "Running…" : "Benchmark") {
                        Task { await runBenchmark() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRunning || !hasDrawing)
                }
                .padding(.horizontal)

                if !results.isEmpty {
                    BenchmarkSummaryView(results: results, ctcBaseline: 15.0)
                }

                Spacer()
            }
            .navigationTitle("Vision Inference Benchmark")
            .sheet(isPresented: $showDebugImage) {
                if let debugImage {
                    VStack(spacing: 16) {
                        Text("Image sent to Vision")
                            .font(.headline)
                        Image(uiImage: debugImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 300, maxHeight: 300)
                            .border(Color.gray)
                        Button("Dismiss") { showDebugImage = false }
                            .buttonStyle(.bordered)
                    }
                    .padding()
                }
            }
        }
    }

    private func runBenchmark() async {
        isRunning = true
        defer { isRunning = false }

        // Render full canvas area (150x150 pt) as the image for Vision
        let drawing = canvasView.drawing
        let canvasSize = CGSize(width: 150, height: 150)
        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(canvasRect)
            let drawingImage = drawing.image(from: canvasRect, scale: 2.0)
            drawingImage.draw(in: canvasRect)
        }
        debugImage = image
        showDebugImage = true
        guard let cgImage = image.cgImage else { return }

        var timings: [Double] = []
        var lastRecognized = ""

        for i in 0..<iterations {
            let start = CACurrentMediaTime()
            await withCheckedContinuation { continuation in
                let request = VNRecognizeTextRequest { req, _ in
                    let elapsed = (CACurrentMediaTime() - start) * 1000
                    timings.append(elapsed)
                    if i == 0, let obs = req.results as? [VNRecognizedTextObservation] {
                        lastRecognized = obs.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                    }
                    continuation.resume()
                }
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                request.minimumTextHeight = 0.0

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try? handler.perform([request])
            }
        }

        recognizedText = lastRecognized.isEmpty ? "(nothing)" : lastRecognized

        let sorted = timings.sorted()
        let mean = timings.reduce(0, +) / Double(timings.count)
        let p50 = sorted[sorted.count / 2]
        let p95 = sorted[Int(Double(sorted.count) * 0.95)]

        results = [
            BenchmarkResult(label: "Mean", ms: mean),
            BenchmarkResult(label: "P50", ms: p50),
            BenchmarkResult(label: "P95", ms: p95),
            BenchmarkResult(label: "Min", ms: sorted.first ?? 0),
            BenchmarkResult(label: "Max", ms: sorted.last ?? 0),
        ]
    }
}

struct BenchmarkResult: Identifiable {
    let id = UUID()
    let label: String
    let ms: Double
}

struct BenchmarkSummaryView: View {
    let results: [BenchmarkResult]
    let ctcBaseline: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Results (Vision OCR vs CTC \(ctcBaseline, specifier: "%.0f")ms baseline)")
                .font(.headline)
                .padding(.horizontal)

            ForEach(results) { r in
                HStack {
                    Text(r.label)
                        .frame(width: 50, alignment: .leading)
                    Text(String(format: "%.2f ms", r.ms))
                        .monospacedDigit()
                        .frame(width: 90, alignment: .trailing)
                    Spacer()
                    let faster = r.ms < ctcBaseline
                    Text(faster ? "✓ faster" : "✗ slower")
                        .foregroundStyle(faster ? .green : .red)
                        .font(.caption)
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

private struct CanvasRepresentable: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    @Binding var hasDrawing: Bool

    func makeCoordinator() -> Coordinator { Coordinator(hasDrawing: $hasDrawing) }

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.tool = PKInkingTool(.pen, color: .black, width: 8)
        canvasView.backgroundColor = .white
        canvasView.delegate = context.coordinator
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        @Binding var hasDrawing: Bool
        init(hasDrawing: Binding<Bool>) { _hasDrawing = hasDrawing }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            hasDrawing = !canvasView.drawing.strokes.isEmpty
        }
    }
}

#Preview {
    VisionBenchmarkView()
}
