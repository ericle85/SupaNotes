import CoreGraphics
import UIKit

struct HersheyGlyph {
  let width: CGFloat
  let strokes: [[CGPoint]]
}

func makeTextStrokes(
  text: String,
  origin: CGPoint,
  scale: CGFloat
) -> [Stroke] {
  let letterSpacing: CGFloat = 2 * scale
  var cursorX = origin.x
  var allStrokes: [Stroke] = []

  for char in text {
    guard let glyph = hersheyGlyphs[char] else {
      continue
    }

    for polyline in glyph.strokes {
      guard polyline.count >= 2 else {
        continue
      }

      let points: [StrokePoint] = polyline.enumerated().map { index, pt in
        StrokePoint(
          location: CGPoint(
            x: cursorX + pt.x * scale,
            y: origin.y + pt.y * scale
          ),
          force: 1.0,
          timestamp: TimeInterval(index) * 0.02
        )
      }

      let stroke = Stroke(
        points: points,
        color: .black,
        width: 2.0
      )
      allStrokes.append(stroke)
    }

    cursorX += (glyph.width * scale + letterSpacing)
  }

  return allStrokes
}

private let hersheyGlyphs: [Character: HersheyGlyph] = [
  "H": HersheyGlyph(
    width: 12,
    strokes: [
      [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 14)],
      [CGPoint(x: 12, y: 0), CGPoint(x: 12, y: 14)],
      [CGPoint(x: 0, y: 7), CGPoint(x: 12, y: 7)],
    ]),

  "W": HersheyGlyph(
    width: 16,
    strokes: [
      [
        CGPoint(x: 0, y: 0), CGPoint(x: 3, y: 14), CGPoint(x: 8, y: 4),
        CGPoint(x: 13, y: 14), CGPoint(x: 16, y: 0),
      ]
    ]),

  "e": HersheyGlyph(
    width: 8,
    strokes: [
      [
        CGPoint(x: 0, y: 9), CGPoint(x: 8, y: 9), CGPoint(x: 8, y: 7),
        CGPoint(x: 6.5, y: 5.5), CGPoint(x: 2, y: 5.5),
        CGPoint(x: 0, y: 7.5), CGPoint(x: 0, y: 12),
        CGPoint(x: 2, y: 14), CGPoint(x: 6, y: 14),
        CGPoint(x: 8, y: 12.5),
      ]
    ]),

  "l": HersheyGlyph(
    width: 2,
    strokes: [
      [CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 14)]
    ]),

  "o": HersheyGlyph(
    width: 9,
    strokes: [
      [
        CGPoint(x: 4.5, y: 5.5), CGPoint(x: 2, y: 6),
        CGPoint(x: 0, y: 8), CGPoint(x: 0, y: 12),
        CGPoint(x: 2, y: 14), CGPoint(x: 4.5, y: 14.5),
        CGPoint(x: 7, y: 14), CGPoint(x: 9, y: 12),
        CGPoint(x: 9, y: 8), CGPoint(x: 7, y: 6),
        CGPoint(x: 4.5, y: 5.5),
      ]
    ]),

  "r": HersheyGlyph(
    width: 6,
    strokes: [
      [CGPoint(x: 0, y: 5.5), CGPoint(x: 0, y: 14)],
      [
        CGPoint(x: 0, y: 9), CGPoint(x: 2, y: 6.5),
        CGPoint(x: 4, y: 5.5), CGPoint(x: 6, y: 5.5),
      ],
    ]),

  "d": HersheyGlyph(
    width: 9,
    strokes: [
      [CGPoint(x: 9, y: 0), CGPoint(x: 9, y: 14)],
      [
        CGPoint(x: 9, y: 8), CGPoint(x: 7, y: 6),
        CGPoint(x: 4.5, y: 5.5), CGPoint(x: 2, y: 6),
        CGPoint(x: 0, y: 8), CGPoint(x: 0, y: 12),
        CGPoint(x: 2, y: 14), CGPoint(x: 4.5, y: 14.5),
        CGPoint(x: 7, y: 14), CGPoint(x: 9, y: 12),
      ],
    ]),

  " ": HersheyGlyph(width: 6, strokes: []),
]
