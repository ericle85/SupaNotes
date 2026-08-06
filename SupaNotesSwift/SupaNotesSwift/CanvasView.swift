import UIKit
import PDFKit

final class CanvasView: UIView {
    private let pdfView = PDFView()
    private var displayLink: CADisplayLink?
    private var zoomPhase: Double = 0
    private var zoomSpeed: Double = 0.5
    private let speedSlider = UISlider()
    private let toggleButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        pdfView.displayMode = .singlePage
        pdfView.autoScales = true
        pdfView.pageShadowsEnabled = false
        pdfView.maxScaleFactor = 8.0
        addSubview(pdfView)

        setupDebugControls()
        loadPDF()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupDebugControls() {
        toggleButton.setTitle("Zoom Loop", for: .normal)
        toggleButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.8)
        toggleButton.setTitleColor(.white, for: .normal)
        toggleButton.layer.cornerRadius = 8
        toggleButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        toggleButton.addTarget(self, action: #selector(toggleZoomLoop), for: .touchUpInside)
        addSubview(toggleButton)

        speedSlider.minimumValue = 0.1
        speedSlider.maximumValue = 3.0
        speedSlider.value = 0.5
        speedSlider.addTarget(self, action: #selector(speedChanged), for: .valueChanged)
        speedSlider.isHidden = true
        addSubview(speedSlider)
    }

    private func loadPDF() {
        guard let pdfURL = Bundle.main.url(forResource: "GraphPaperBackground", withExtension: "pdf") else { return }
        pdfView.document = PDFDocument(url: pdfURL)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        pdfView.frame = bounds
        toggleButton.frame = CGRect(x: 20, y: bounds.height - 100, width: 120, height: 40)
        speedSlider.frame = CGRect(x: 150, y: bounds.height - 95, width: 200, height: 30)
    }

    @objc private func toggleZoomLoop() {
        if displayLink != nil {
            stopZoomLoop()
        } else {
            startZoomLoop()
        }
    }

    private func startZoomLoop() {
        zoomPhase = 0
        speedSlider.isHidden = false
        toggleButton.setTitle("Stop", for: .normal)
        toggleButton.backgroundColor = UIColor.systemRed.withAlphaComponent(0.8)

        let link = CADisplayLink(target: self, selector: #selector(zoomTick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopZoomLoop() {
        displayLink?.invalidate()
        displayLink = nil
        speedSlider.isHidden = true
        toggleButton.setTitle("Zoom Loop", for: .normal)
        toggleButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.8)
    }

    @objc private func speedChanged() {
        zoomSpeed = Double(speedSlider.value)
    }

    @objc private func zoomTick() {
        guard let link = displayLink else { return }
        zoomPhase += link.duration * zoomSpeed

        let t = (sin(zoomPhase) + 1) / 2
        let minScale = pdfView.minScaleFactor
        let maxScale = pdfView.maxScaleFactor
        let scale = minScale + (maxScale - minScale) * t
        pdfView.scaleFactor = scale
    }
}
