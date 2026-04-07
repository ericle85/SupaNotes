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

        // Force layout to populate displayList
        let fitSize = label.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude,
                                                 height: CGFloat.greatestFiniteMagnitude))

        guard fitSize.width > 0, fitSize.height > 0 else { return nil }
        guard let displayList = label.displayList else { return nil }

        // Add padding to avoid clipping
        let padding: CGFloat = 4
        let totalWidth = fitSize.width + padding * 2
        let totalHeight = fitSize.height + padding * 2

        label.frame = CGRect(x: 0, y: 0, width: totalWidth, height: totalHeight)

        // Extract glyph rects in CoreText coordinates (y-up, origin at baseline)
        let ctGlyphRects = extractGlyphRects(from: displayList)

        // Render to UIImage
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: totalWidth, height: totalHeight))
        let image = renderer.image { ctx in
            // White background for debugging visibility
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: totalWidth, height: totalHeight))

            let cgContext = ctx.cgContext

            // Flip to CoreText coordinates
            cgContext.translateBy(x: padding, y: totalHeight - padding)
            cgContext.scaleBy(x: 1, y: -1)

            // Offset to account for displayList position
            cgContext.translateBy(x: displayList.position.x, y: displayList.position.y)

            displayList.draw(cgContext)
        }

        // Convert glyph rects from CoreText coords to UIKit coords
        let uikitRects = ctGlyphRects.map { glyph -> GlyphRect in
            let ctRect = glyph.rect
            // In CoreText: y is up from baseline. In UIKit image: y is down from top.
            // displayList.position is the baseline offset set by MTMathUILabel
            let x = ctRect.origin.x + displayList.position.x + padding
            let y = totalHeight - padding - (ctRect.origin.y + ctRect.height + displayList.position.y)
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
