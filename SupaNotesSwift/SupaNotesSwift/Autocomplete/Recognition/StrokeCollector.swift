import Foundation
import PencilKit

struct StrokeLine {
  var strokeIndices: [Int]
  var yMin: CGFloat
  var yMax: CGFloat
}

func strokeYOverlapsLine(_ line: StrokeLine, _ strokeYMin: CGFloat, _ strokeYMax: CGFloat) -> Bool {
  let lineHeight = line.yMax - line.yMin
  let tolerance = lineHeight * 0.4
  return (line.yMin - tolerance) <= strokeYMax && strokeYMin <= line.yMax
}

func convertPKStrokesToStrokePoints(_ strokes: [PKStroke]) -> [[StrokePoint]] {
  let strokeGap: Float = 0.05
  var result = [[StrokePoint]]()
  var cumulativeTime: Float = 0

  for stroke in strokes {
    let path = stroke.path
    var points = [StrokePoint]()
    points.reserveCapacity(path.count)

    for i in 0..<path.count {
      let point = path[i]
      points.append(
        StrokePoint(
          x: Float(point.location.x),
          y: Float(point.location.y),
          t: cumulativeTime + Float(point.timeOffset)
        )
      )
    }

    if let lastTime = points.last?.t {
      cumulativeTime = lastTime + strokeGap
    }
    result.append(points)
  }

  return result
}

final class StrokeCollector {
  var drawingProvider: (() -> PKDrawing)?
  var onLinesChanged: (([CGRect]) -> Void)?
  var onSuggestionNeeded: ((_ strokes: [[StrokePoint]]) -> Void)?
  var isSuggestionActive = false

  private var lines: [StrokeLine] = []
  private var knownStrokeCount = 0
  private var strokesSinceLastSuggestion = 0

  func resetSuggestionCounter() {
    strokesSinceLastSuggestion = 0
  }

  func pencilLifted() {
    guard let drawing = drawingProvider?() else { return }
    let strokes = drawing.strokes

    if strokes.count < knownStrokeCount {
      rebuildLines(from: strokes)
      return
    }

    guard strokes.count > knownStrokeCount else { return }

    for i in knownStrokeCount..<strokes.count {
      addStrokeToLine(stroke: strokes[i], index: i)
    }
    knownStrokeCount = strokes.count

    let lastIndex = strokes.count - 1
    guard let line = lines.first(where: { $0.strokeIndices.contains(lastIndex) }) else {
      reportLineRects(strokes: strokes)
      return
    }

    let lineStrokes = line.strokeIndices.map { strokes[$0] }
    let converted = convertPKStrokesToStrokePoints(lineStrokes)

    Task {
      _ = try? await ocr(strokes: converted)
    }

    if !isSuggestionActive {
      strokesSinceLastSuggestion += 1
      if strokesSinceLastSuggestion >= 3 {
        strokesSinceLastSuggestion = 0
        onSuggestionNeeded?(converted)
      }
    }

    reportLineRects(strokes: strokes)
  }

  private func addStrokeToLine(stroke: PKStroke, index: Int) {
    let bounds = stroke.renderBounds
    let sYMin = bounds.minY
    let sYMax = bounds.maxY

    var overlapping: [Int] = []
    for (i, line) in lines.enumerated() {
      if strokeYOverlapsLine(line, sYMin, sYMax) {
        overlapping.append(i)
      }
    }

    if overlapping.isEmpty {
      lines.append(StrokeLine(strokeIndices: [index], yMin: sYMin, yMax: sYMax))
      return
    }

    if overlapping.count == 1 {
      let idx = overlapping[0]
      lines[idx].strokeIndices.append(index)
      lines[idx].yMin = min(lines[idx].yMin, sYMin)
      lines[idx].yMax = max(lines[idx].yMax, sYMax)
      return
    }

    var merged = StrokeLine(strokeIndices: [index], yMin: sYMin, yMax: sYMax)
    for i in overlapping {
      merged.strokeIndices.append(contentsOf: lines[i].strokeIndices)
      merged.yMin = min(merged.yMin, lines[i].yMin)
      merged.yMax = max(merged.yMax, lines[i].yMax)
    }
    for i in overlapping.reversed() {
      lines.remove(at: i)
    }
    lines.append(merged)
  }

  private func rebuildLines(from strokes: [PKStroke]) {
    lines = []
    for i in 0..<strokes.count {
      addStrokeToLine(stroke: strokes[i], index: i)
    }
    knownStrokeCount = strokes.count
    reportLineRects(strokes: strokes)
  }

  private func reportLineRects(strokes: [PKStroke]) {
    let rects = lines.map { line -> CGRect in
      let lineStrokes = line.strokeIndices.map { strokes[$0] }
      return lineStrokes.reduce(CGRect.null) { $0.union($1.renderBounds) }
    }
    onLinesChanged?(rects)
  }
}
