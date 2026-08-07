import CoreGraphics
import Foundation
import PencilKit
import UIKit

final class PageView: UIView, PKCanvasViewDelegate {
  private var backgroundView: UIView?
  private let drawingCanvas = PKCanvasView()
  private let toolPicker = PKToolPicker()
  private var idleTimer: Timer?
  private var lastSentStrokeCount = 0

  static let defaultPageSize = CGSize(width: 612, height: 792)
  private static let idleTimeout: TimeInterval = 0.8

  init(page: Page) {
    let pageSize = Self.pageSizeFor(page.background)
    super.init(frame: CGRect(origin: .zero, size: pageSize))
    setBackground(page.background)
    setupDrawingCanvas(size: pageSize)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError()
  }

  private func setupDrawingCanvas(size: CGSize) {
    drawingCanvas.frame = CGRect(origin: .zero, size: size)
    drawingCanvas.isScrollEnabled = false
    drawingCanvas.backgroundColor = .clear
    drawingCanvas.isOpaque = false
    drawingCanvas.drawingPolicy = .pencilOnly
    drawingCanvas.delegate = self
    addSubview(drawingCanvas)

    toolPicker.setVisible(true, forFirstResponder: drawingCanvas)
    toolPicker.addObserver(drawingCanvas)
    drawingCanvas.becomeFirstResponder()
  }

  func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
    idleTimer?.invalidate()
    idleTimer = Timer.scheduledTimer(
      withTimeInterval: Self.idleTimeout,
      repeats: false
    ) { [weak self] _ in
      self?.onIdleTimerFired()
    }
  }

  private func onIdleTimerFired() {
    let allStrokes = drawingCanvas.drawing.strokes
    let newStrokes = Array(allStrokes[lastSentStrokeCount...])
    if newStrokes.isEmpty { return }
    lastSentStrokeCount = allStrokes.count

    let strokeData = convertStrokesToJSON(newStrokes)
    runPipeline(strokeData: strokeData)
  }

  private func convertStrokesToJSON(_ strokes: [PKStroke]) -> [[[Double]]] {
    let groupStartTime = strokes.first?.path.creationDate.timeIntervalSince1970 ?? 0

    return strokes.map { stroke in
      (0..<stroke.path.count).map { index in
        let point = stroke.path[index]
        let absoluteTime = stroke.path.creationDate.timeIntervalSince1970 + point.timeOffset
        let relativeMs = (absoluteTime - groupStartTime) * 1000.0
        return [Double(point.location.x), Double(point.location.y), relativeMs]
      }
    }
  }

  private static let pipelineURL = URL(string: "http://100.90.35.22:5555")!

  private func runPipeline(strokeData: [[[Double]]]) {
    guard let jsonData = try? JSONSerialization.data(withJSONObject: strokeData) else {
      print("[Pipeline] Failed to serialize strokes")
      return
    }

    var request = URLRequest(url: Self.pipelineURL)
    request.httpMethod = "POST"
    request.httpBody = jsonData
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    URLSession.shared.dataTask(with: request) { data, _, error in
      if let error = error {
        print("[Pipeline] Error: \(error.localizedDescription)")
        return
      }
      if let data = data, let output = String(data: data, encoding: .utf8) {
        print("[Pipeline] Result: \(output)")
      }
    }.resume()
  }

  private func setBackground(_ background: PageBackground) {
    backgroundView?.removeFromSuperview()

    let pageSize = Self.pageSizeFor(background)
    let bgView: UIView

    switch background {
    case .grid(let theme):
      bgView = GridBackgroundView(theme: theme, size: pageSize)
    case .pdf(let pdfPage):
      let pdfView = TiledBackgroundView(pdfPage: pdfPage)
      pdfView.frame = CGRect(origin: .zero, size: pageSize)
      bgView = pdfView
    }

    frame = CGRect(origin: frame.origin, size: pageSize)
    addSubview(bgView)
    backgroundView = bgView
  }

  static func pageSizeFor(_ background: PageBackground) -> CGSize {
    switch background {
    case .grid:
      return defaultPageSize
    case .pdf(let page):
      return page.getBoxRect(.mediaBox).size
    }
  }
}
