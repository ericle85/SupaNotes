import UIKit
import SwiftMath

struct SwiftMathRenderResult {
    let image: UIImage
    let size: CGSize
    let glyphRects: [GlyphRect]
}

struct SwiftMathRenderer {

    /// Render a LaTeX string to a UIImage and extract per-glyph bounding rects.
    /// Rects are in UIKit coordinates (origin top-left, y-down).
    func render(latex: String, fontSize: CGFloat, textColor: UIColor = .darkGray) -> SwiftMathRenderResult? {
        let label = MTMathUILabel()
        label.latex = latex
        label.fontSize = fontSize
        label.textColor = MTColor(cgColor: textColor.cgColor)
        label.labelMode = .display

        // Compute intrinsic size — use a large frame so layout has room
        label.frame = CGRect(x: 0, y: 0, width: 2000, height: 2000)
        label.setNeedsLayout()
        label.layoutIfNeeded()

        guard let displayList = label.displayList else { return nil }

        // Use the display tree's actual metrics for sizing
        let contentWidth = displayList.width
        let contentAscent = displayList.ascent
        let contentDescent = displayList.descent
        guard contentWidth > 0, (contentAscent + contentDescent) > 0 else { return nil }

        let padding: CGFloat = 8
        let totalWidth = contentWidth + padding * 2
        let totalHeight = contentAscent + contentDescent + padding * 2

        // Reset displayList position to origin so we control placement
        displayList.position = CGPoint.zero

        let baselineY = padding + contentAscent

        // Extract glyph rects in CoreText coordinates (y-up from origin)
        let ctGlyphRects = extractGlyphRects(from: displayList)

        // Render to UIImage
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: totalWidth, height: totalHeight))
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: totalWidth, height: totalHeight))

            let cgContext = ctx.cgContext

            // CoreText draws with y-up. We want baseline at baselineY from top.
            // Flip y, then translate so origin (baseline) maps to (padding, baselineY)
            cgContext.translateBy(x: padding, y: baselineY)
            cgContext.scaleBy(x: 1, y: -1)

            displayList.draw(cgContext)
        }

        // Convert glyph rects from CoreText coords (y-up from baseline) to UIKit coords (y-down from top)
        let uikitRects = ctGlyphRects.map { glyph -> GlyphRect in
            let ctRect = glyph.rect
            // ctRect.origin.y is in CoreText coords (positive = above baseline)
            // In UIKit: y = baselineY - (ctRect.origin.y + ctRect.height)
            let x = ctRect.origin.x + padding
            let y = baselineY - (ctRect.origin.y + ctRect.height)
            let uiRect = CGRect(x: x, y: y, width: ctRect.width, height: ctRect.height)
            return GlyphRect(character: glyph.character, rect: uiRect)
        }

        return SwiftMathRenderResult(
            image: image,
            size: CGSize(width: totalWidth, height: totalHeight),
            glyphRects: uikitRects
        )
    }

    /// Render with debug bounding boxes drawn on the image.
    func renderWithDebug(latex: String, fontSize: CGFloat, textColor: UIColor = .darkGray) -> SwiftMathRenderResult? {
        guard let result = render(latex: latex, fontSize: fontSize, textColor: textColor) else { return nil }

        let colors: [UIColor] = [.systemRed, .systemBlue, .systemGreen, .systemOrange,
                                  .systemPurple, .systemTeal, .systemPink, .systemYellow]

        let renderer = UIGraphicsImageRenderer(size: result.size)
        let debugImage = renderer.image { ctx in
            result.image.draw(at: .zero)

            for (i, glyph) in result.glyphRects.enumerated() {
                let color = colors[i % colors.count]
                color.withAlphaComponent(0.3).setFill()
                ctx.fill(glyph.rect)
                color.setStroke()
                UIBezierPath(rect: glyph.rect).stroke()
            }
        }

        return SwiftMathRenderResult(
            image: debugImage,
            size: result.size,
            glyphRects: result.glyphRects
        )
    }
}
