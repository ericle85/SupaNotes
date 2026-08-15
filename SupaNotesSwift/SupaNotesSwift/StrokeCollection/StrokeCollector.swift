import Foundation
import PencilKit

func convertPKStrokeToStrokePoints(_ stroke: PKStroke) -> [StrokePoint] {
  let path = stroke.path
  var points = [StrokePoint]()
  points.reserveCapacity(path.count)

  for i in 0..<path.count {
    let point = path[i]
    points.append(
      StrokePoint(
        x: Float(point.location.x),
        y: Float(point.location.y),
        t: Float(point.timeOffset)
      ))
  }

  return points
}

final class StrokeCollector {
  private var lastProcessedStrokeCount = 0
  private var debounceTimer: Timer?
  var onBoundingBox: ((CGRect) -> Void)?
  var onScribbleDetected: ((CGRect, Int) -> Void)?

  var drawingProvider: (() -> PKDrawing)?

  func syncStrokeCount() {
    guard let drawing = drawingProvider?() else { return }
    lastProcessedStrokeCount = drawing.strokes.count
  }

  func pencilLifted() {
    debounceTimer?.invalidate()
    debounceTimer = Timer.scheduledTimer(
      withTimeInterval: 0.75,
      repeats: false
    ) { [weak self] _ in
      guard let self, let drawing = self.drawingProvider?() else { return }
      self.flushStrokes(drawing: drawing)
    }
  }

  func pencilTouched() {
    debounceTimer?.invalidate()
    debounceTimer = nil
  }

  private func flushStrokes(drawing: PKDrawing) {
    let allStrokes = drawing.strokes
    let currentCount = allStrokes.count

    if currentCount <= lastProcessedStrokeCount {
      return
    }

    let newStrokes = allStrokes[lastProcessedStrokeCount..<currentCount]
    lastProcessedStrokeCount = currentCount

    var boundingBox = CGRect.null
    for stroke in newStrokes {
      boundingBox = boundingBox.union(stroke.renderBounds)
    }
    onBoundingBox?(boundingBox)

    let converted = newStrokes.map { convertPKStrokeToStrokePoints($0) }
    let scribbleBounds = boundingBox
    let scribbleStartIndex = lastProcessedStrokeCount - newStrokes.count

    Task { [weak self] in
      let kind = await runAutocompletePipeline(strokes: converted)
      if kind == "scribble" {
        await MainActor.run {
          self?.onScribbleDetected?(scribbleBounds, scribbleStartIndex)
        }
      }
    }
  }
}
