import UIKit

struct MathLayoutResult {
    let image: UIImage
    let size: CGSize
    let characters: [OverlayCharacter]
}

final class MathLayoutEngine {
    private let debugColors: [UIColor] = [.red, .blue, .green, .orange, .purple, .magenta, .cyan, .yellow]
    private var charIndex = 0

    // MARK: - Font

    private func mathFont(size: CGFloat) -> UIFont {
        UIFont(name: "CMU Serif", size: size)
            ?? UIFont(name: "TimesNewRomanPSMT", size: size)
            ?? UIFont.systemFont(ofSize: size)
    }

    private func mathFontItalic(size: CGFloat) -> UIFont {
        UIFont(name: "CMU Serif Italic", size: size)
            ?? UIFont(name: "TimesNewRomanPS-ItalicMT", size: size)
            ?? UIFont.italicSystemFont(ofSize: size)
    }

    // Characters with uniform handwriting → tighter box
    private let narrowChars: Set<String> = ["i", "l", "1", "!", ".", ",", ";", ":", "'", "|"]
    private let wideChars: Set<String> = ["m", "w", "M", "W"]
    // Greek uppercase should be roman (not italic) per LaTeX convention
    private let romanChars: Set<String> = [
        "Γ", "Δ", "Θ", "Λ", "Ξ", "Π", "Σ", "Φ", "Ψ", "Ω",
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
        "+", "−", "=", "<", ">", "≤", "≥", "≠", "≈", "≡",
        "±", "∓", "×", "÷", "·", "(", ")", "[", "]", "{", "}",
        "|", ",", ".", ";", ":", "!", "?", "/",
    ]

    // MARK: - Public

    func layout(nodes: [MathNode], fontSize: CGFloat, drawDebugBoxes: Bool = true) -> MathLayoutResult {
        charIndex = 0
        let root = UIView()
        root.backgroundColor = .clear
        root.clipsToBounds = false

        let rowView = layoutRow(nodes, fontSize: fontSize)
        root.addSubview(rowView)

        let padding: CGFloat = max(12, fontSize * 0.4)

        // Calculate visual bounds including overflow from clipsToBounds=false containers (e.g. integrals)
        let visualRect = visualBounds(of: rowView, relativeTo: rowView)
        let overflowTop = max(0, -visualRect.minY)
        let overflowBottom = max(0, visualRect.maxY - rowView.frame.height)
        let overflowLeft = max(0, -visualRect.minX)
        let overflowRight = max(0, visualRect.maxX - rowView.frame.width)

        let totalW = rowView.frame.width + overflowLeft + overflowRight + padding * 2
        let totalH = rowView.frame.height + overflowTop + overflowBottom + padding * 2
        rowView.frame.origin = CGPoint(x: padding + overflowLeft, y: padding + overflowTop)
        let size = CGSize(width: totalW, height: totalH)
        root.frame = CGRect(origin: .zero, size: size)

        var characters: [OverlayCharacter] = []
        collectCharacters(from: root, relativeTo: root, into: &characters)

        if drawDebugBoxes {
            for char in characters {
                let box = UIView(frame: char.rect)
                box.backgroundColor = .clear
                box.layer.borderColor = debugColors[char.index % debugColors.count].cgColor
                box.layer.borderWidth = 2
                root.addSubview(box)
            }
        }

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            root.layer.render(in: ctx.cgContext)
        }

        return MathLayoutResult(image: image, size: size, characters: characters)
    }

    // MARK: - Row Layout

    /// Each layoutNode returns (view, baselineY) where baselineY = distance from top of view to the alignment baseline.
    private func layoutRow(_ nodes: [MathNode], fontSize: CGFloat) -> UIView {
        let container = UIView()
        var items: [(UIView, CGFloat)] = [] // (view, baselineY)

        for node in nodes {
            let (view, baselineY) = layoutNode(node, fontSize: fontSize)
            items.append((view, baselineY))
        }

        // Align all items on their baseline
        var maxAbove: CGFloat = 0  // max distance from baseline to top
        var maxBelow: CGFloat = 0  // max distance from baseline to bottom
        for (view, baselineY) in items {
            maxAbove = max(maxAbove, baselineY)
            maxBelow = max(maxBelow, view.frame.height - baselineY)
        }

        let totalHeight = maxAbove + maxBelow
        var x: CGFloat = 0
        for (view, baselineY) in items {
            let y = maxAbove - baselineY
            view.frame.origin = CGPoint(x: x, y: y)
            container.addSubview(view)
            x += view.frame.width + fontSize * 0.08
        }

        container.frame = CGRect(x: 0, y: 0, width: x, height: totalHeight)
        return container
    }

    /// Returns (view, baselineY) — baselineY is distance from top of view to alignment baseline.
    private func layoutNode(_ node: MathNode, fontSize: CGFloat) -> (UIView, CGFloat) {
        switch node {
        case .glyph(let text):
            let view = makeGlyphLabel(text, fontSize: fontSize)
            return (view, glyphBaselineY(text, view: view, fontSize: fontSize))
        case .text(let text):
            let view = makeTextView(text, fontSize: fontSize)
            return (view, view.frame.height * 0.78)
        case .space:
            let view = UIView(frame: CGRect(x: 0, y: 0, width: fontSize * 0.25, height: fontSize))
            return (view, fontSize * 0.78)
        case .fracLine:
            let view = makeFracLine(width: fontSize * 1.5, fontSize: fontSize)
            return (view, view.frame.height / 2)
        case .sqrt(let content):
            return layoutSqrt(content: content, fontSize: fontSize)
        case .accent(let symbol, let content):
            return layoutAccent(symbol: symbol, content: content, fontSize: fontSize)
        case .fraction(let num, let den):
            return layoutFraction(num: num, den: den, fontSize: fontSize)
        case .script(let base, let sub, let sup):
            return layoutScript(base: base, sub: sub, sup: sup, fontSize: fontSize)
        case .delimited(let open, let close, let content):
            return layoutDelimited(open: open, close: close, content: content, fontSize: fontSize)
        case .matrix(let rows, let open, let close):
            return layoutMatrix(rows: rows, open: open, close: close, fontSize: fontSize)
        case .row(let nodes):
            let view = layoutRow(nodes, fontSize: fontSize)
            return (view, view.frame.height * 0.78)
        }
    }

    /// Compute baseline Y for a glyph view (tight bbox container)
    private func glyphBaselineY(_ text: String, view: UIView, fontSize: CGFloat) -> CGFloat {
        if tallGlyphs.contains(text) {
            // Integral: bbox is the stem portion, baseline at center + math axis shift
            return view.frame.height / 2 + fontSize * 0.32
        }
        // With tight bbox: baseline position depends on character type
        if descenderChars.contains(text) {
            // Baseline is above the descender portion
            // bbox spans from (baseline - xHeight) to (baseline + |descender|)
            // so baseline is at xHeight / (xHeight + |descender|) from top
            let font = mathFontItalic(size: fontSize)
            let xH = font.xHeight
            let desc = abs(font.descender)
            return xH / (xH + desc) * view.frame.height
        }
        // For non-descender chars, baseline is at the bottom of the tight bbox
        return view.frame.height - fontSize * 0.03  // minus the padding
    }

    // MARK: - Glyph

    private let tallGlyphs: Set<String> = ["∫", "∮"]

    private let descenderChars: Set<String> = ["g", "j", "p", "q", "y", "Q", "β", "γ", "η", "μ", "ρ", "φ", "χ", "ψ"]
    private let capitalChars: Set<String> = [
        "A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z",
        "Γ","Δ","Θ","Λ","Ξ","Π","Σ","Φ","Ψ","Ω",
        "∞","∂","∇","∑","∏","∀","∃",
    ]

    private func makeGlyphLabel(_ text: String, fontSize: CGFloat) -> UIView {
        let label = UILabel()
        label.text = text
        let isRoman = romanChars.contains(text) || text.count > 1
        let effectiveSize = tallGlyphs.contains(text) ? fontSize * 1.6 : fontSize
        let font = isRoman ? mathFont(size: effectiveSize) : mathFontItalic(size: effectiveSize)
        label.font = font
        label.textColor = .black
        label.sizeToFit()

        let baseWidth = label.frame.width
        let width: CGFloat
        if narrowChars.contains(text) {
            width = max(baseWidth, fontSize * 0.45)
        } else if wideChars.contains(text) {
            width = max(baseWidth, fontSize * 0.9)
        } else {
            width = max(baseWidth, fontSize * 0.55)
        }
        label.frame.size.width = width
        label.frame.size.height = max(label.frame.height, fontSize * 0.9)
        label.textAlignment = .center

        if tallGlyphs.contains(text) {
            // Integral: render full size but bounding box covers only the vertical stem
            let container = UIView()
            container.clipsToBounds = false
            container.tag = 9000 + charIndex
            charIndex += 1
            let bboxH = label.frame.height * 0.55
            let bboxY = (label.frame.height - bboxH) / 2
            container.frame = CGRect(x: 0, y: 0, width: width, height: bboxH)
            label.frame.origin = CGPoint(x: 0, y: -bboxY)
            container.addSubview(label)
            return container
        }

        // Tight bounding box using font metrics
        // Label layout: baseline is at (label.height - font.descender) from top
        // (descender is negative, so baseline = height + descender)
        let labelBaseline = label.frame.height + font.descender
        let tightTop: CGFloat
        let tightBottom: CGFloat

        if capitalChars.contains(text) || text.first?.isUppercase == true {
            tightTop = labelBaseline - font.capHeight
            tightBottom = labelBaseline  // no descender
        } else if descenderChars.contains(text) {
            tightTop = labelBaseline - font.xHeight
            tightBottom = labelBaseline - font.descender  // descender is negative
        } else {
            // Lowercase without descender (x, a, n, etc.) or symbols
            tightTop = labelBaseline - font.xHeight
            tightBottom = labelBaseline
        }

        // Add small padding so strokes aren't clipped
        let pad: CGFloat = fontSize * 0.03
        let bboxTop = max(0, tightTop - pad)
        let bboxBottom = min(label.frame.height, tightBottom + pad)
        let bboxH = bboxBottom - bboxTop

        let container = UIView()
        container.clipsToBounds = false
        container.tag = 9000 + charIndex
        charIndex += 1
        container.frame = CGRect(x: 0, y: 0, width: width, height: bboxH)
        label.frame.origin = CGPoint(x: 0, y: -bboxTop)
        container.addSubview(label)
        return container
    }

    private func makeTextView(_ text: String, fontSize: CGFloat) -> UIView {
        let container = UIView()
        var x: CGFloat = 0
        for ch in text {
            let label = UILabel()
            label.text = String(ch)
            label.font = mathFont(size: fontSize)
            label.textColor = .black
            label.tag = 9000 + charIndex
            charIndex += 1
            label.sizeToFit()
            let chStr = String(ch)
            let w = narrowChars.contains(chStr) ? max(label.frame.width, fontSize * 0.35) : max(label.frame.width, fontSize * 0.5)
            label.frame.size = CGSize(width: w, height: max(label.frame.height, fontSize * 0.9))
            label.textAlignment = .center
            label.frame.origin = CGPoint(x: x, y: 0)
            container.addSubview(label)
            x += label.frame.width + fontSize * 0.02 // small gap to prevent overlap
        }
        container.frame = CGRect(x: 0, y: 0, width: x, height: fontSize * 1.1)
        return container
    }

    // MARK: - Fraction

    private func layoutFraction(num: [MathNode], den: [MathNode], fontSize: CGFloat) -> (UIView, CGFloat) {
        let container = UIView()
        let fracFontSize = fontSize * 0.75

        let numView = layoutRow(num, fontSize: fracFontSize)
        let denView = layoutRow(den, fontSize: fracFontSize)
        let lineWidth = max(numView.frame.width, denView.frame.width) + fontSize * 0.2
        let lineHeight: CGFloat = max(2, fontSize * 0.04)
        let gap: CGFloat = fontSize * 0.06

        // Fraction line — ensure min height for bounding box visibility
        let line = UIView()
        line.backgroundColor = .black
        line.tag = 9000 + charIndex
        charIndex += 1
        line.frame = CGRect(x: 0, y: numView.frame.height + gap, width: lineWidth, height: lineHeight)

        numView.frame.origin = CGPoint(x: (lineWidth - numView.frame.width) / 2, y: 0)
        denView.frame.origin = CGPoint(x: (lineWidth - denView.frame.width) / 2, y: line.frame.maxY + gap)

        container.addSubview(numView)
        container.addSubview(line)
        container.addSubview(denView)

        let totalHeight = denView.frame.maxY
        container.frame = CGRect(x: 0, y: 0, width: lineWidth, height: totalHeight)

        // Fraction bar should align with math axis of surrounding text.
        // Math axis ≈ baseline - 0.35*fontSize. So reported baselineY =
        // line.midY + (textBaseline - mathAxis) = line.midY + 0.32*fontSize
        let mathAxisShift = fontSize * 0.32
        return (container, line.frame.midY + mathAxisShift)
    }

    private func makeFracLine(width: CGFloat, fontSize: CGFloat) -> UIView {
        let line = UIView()
        line.backgroundColor = .black
        line.tag = 9000 + charIndex
        charIndex += 1
        line.frame = CGRect(x: 0, y: 0, width: width, height: max(2, fontSize * 0.04))
        return line
    }

    // MARK: - Accent

    private func layoutAccent(symbol: String, content: [MathNode], fontSize: CGFloat) -> (UIView, CGFloat) {
        let container = UIView()
        let contentView = layoutRow(content, fontSize: fontSize)
        let contentW = contentView.frame.width
        let contentH = contentView.frame.height

        if symbol == "_" {
            // Underline
            let gap: CGFloat = fontSize * 0.02
            contentView.frame.origin = .zero
            container.addSubview(contentView)
            let line = UIView()
            line.backgroundColor = .black
            line.tag = 9000 + charIndex
            charIndex += 1
            line.frame = CGRect(x: 0, y: contentH + gap, width: contentW, height: max(2, fontSize * 0.04))
            container.addSubview(line)
            container.frame = CGRect(x: 0, y: 0, width: contentW, height: line.frame.maxY)
            return (container, contentH * 0.78)
        }

        if symbol == "—" {
            // Overline/bar: bar sits above content, no overlap
            let lineH = max(2, fontSize * 0.04)
            let line = UIView()
            line.backgroundColor = .black
            line.tag = 9000 + charIndex
            charIndex += 1
            line.frame = CGRect(x: 0, y: 0, width: contentW, height: lineH)
            container.addSubview(line)
            contentView.frame.origin = CGPoint(x: 0, y: lineH)
            container.addSubview(contentView)
            let totalH = lineH + contentH
            container.frame = CGRect(x: 0, y: 0, width: contentW, height: totalH)
            return (container, lineH + contentH * 0.78)
        }

        // Accent shape above content — no overlap, shapes draw within their bounds
        let accentView = AccentShapeView(symbol: symbol, width: contentW, fontSize: fontSize)
        accentView.tag = 9000 + charIndex
        charIndex += 1
        let accentH = accentView.frame.height

        accentView.frame.origin = CGPoint(x: 0, y: 0)
        container.addSubview(accentView)
        contentView.frame.origin = CGPoint(x: 0, y: accentH)
        container.addSubview(contentView)

        let totalH = accentH + contentH
        container.frame = CGRect(x: 0, y: 0, width: contentW, height: totalH)
        return (container, accentH + contentH * 0.78)
    }

    // MARK: - Square Root

    private func layoutSqrt(content: [MathNode], fontSize: CGFloat) -> (UIView, CGFloat) {
        let container = UIView()
        let contentView = layoutRow(content, fontSize: fontSize)

        let lineThickness: CGFloat = max(1.5, fontSize * 0.035)
        let topPad: CGFloat = fontSize * 0.08
        let contentH = contentView.frame.height
        let contentW = contentView.frame.width + fontSize * 0.1
        let totalH = contentH + topPad + lineThickness

        let hookWidth = fontSize * 0.12
        let surdWidth = fontSize * 0.3
        let symbolWidth = hookWidth + surdWidth
        let vinculumEnd = symbolWidth + contentW

        let sqrtView = SqrtShapeView(
            frame: CGRect(x: 0, y: 0, width: vinculumEnd, height: totalH),
            hookWidth: hookWidth, surdWidth: surdWidth, lineThickness: lineThickness
        )
        sqrtView.backgroundColor = .clear
        sqrtView.tag = 9000 + charIndex
        charIndex += 1
        container.addSubview(sqrtView)

        let contentY = lineThickness + topPad
        contentView.frame.origin = CGPoint(x: symbolWidth, y: contentY)
        container.addSubview(contentView)

        container.frame = CGRect(x: 0, y: 0, width: vinculumEnd, height: totalH)
        // Baseline = content's baseline + content offset from top
        return (container, contentY + contentView.frame.height * 0.78)
    }

    // MARK: - Script

    private let limitsOperators: Set<String> = ["∑", "∏", "lim", "max", "min", "sup", "inf"]

    private func isLimitsOperator(_ node: MathNode) -> Bool {
        if case .glyph(let t) = node { return limitsOperators.contains(t) }
        if case .text(let t) = node { return limitsOperators.contains(t) }
        return false
    }

    private func isIntegral(_ node: MathNode) -> Bool {
        if case .glyph(let t) = node { return t == "∫" || t == "∮" }
        return false
    }

    private func layoutScript(base: MathNode, sub: [MathNode]?, sup: [MathNode]?, fontSize: CGFloat) -> (UIView, CGFloat) {
        if isLimitsOperator(base) {
            return layoutLimitsScript(base: base, sub: sub, sup: sup, fontSize: fontSize)
        }
        return layoutInlineScript(base: base, sub: sub, sup: sup, fontSize: fontSize)
    }

    /// Limits-style: sub/sup above and below (∑, ∏, lim, etc.)
    private func layoutLimitsScript(base: MathNode, sub: [MathNode]?, sup: [MathNode]?, fontSize: CGFloat) -> (UIView, CGFloat) {
        let container = UIView()
        let scriptFontSize = fontSize * 0.45
        let gap = fontSize * 0.03

        let (baseView, baseBaselineY) = layoutNode(base, fontSize: fontSize * 1.2)

        var supView: UIView?
        var subView: UIView?
        if let sup = sup { supView = layoutRow(sup, fontSize: scriptFontSize) }
        if let sub = sub { subView = layoutRow(sub, fontSize: scriptFontSize) }

        let maxWidth = max(baseView.frame.width,
                          max(supView?.frame.width ?? 0, subView?.frame.width ?? 0))
        var y: CGFloat = 0

        if let sv = supView {
            sv.frame.origin = CGPoint(x: (maxWidth - sv.frame.width) / 2, y: y)
            container.addSubview(sv)
            y += sv.frame.height + gap
        }

        let baseY = y
        baseView.frame.origin = CGPoint(x: (maxWidth - baseView.frame.width) / 2, y: y)
        container.addSubview(baseView)
        y += baseView.frame.height + gap

        if let sv = subView {
            sv.frame.origin = CGPoint(x: (maxWidth - sv.frame.width) / 2, y: y)
            container.addSubview(sv)
            y += sv.frame.height
        }

        container.frame = CGRect(x: 0, y: 0, width: maxWidth, height: y)
        // Baseline at the base operator's baseline
        return (container, baseY + baseBaselineY)
    }

    /// Inline-style: sub/sup to the right
    private func layoutInlineScript(base: MathNode, sub: [MathNode]?, sup: [MathNode]?, fontSize: CGFloat) -> (UIView, CGFloat) {
        let container = UIView()
        let scriptFontSize = fontSize * 0.6

        let (baseView, baseBaselineY) = layoutNode(base, fontSize: fontSize)
        container.addSubview(baseView)

        let scriptGap = fontSize * 0.02
        // For integrals, place limits to the right of the symbol (past the curls)
        let scriptX = isIntegral(base) ? baseView.frame.width + scriptGap : baseView.frame.width + scriptGap

        var totalWidth = baseView.frame.width
        var totalHeight = baseView.frame.height
        var topExtension: CGFloat = 0
        var bottomExtension: CGFloat = 0

        if let sup = sup {
            let supView = layoutRow(sup, fontSize: scriptFontSize)
            if isIntegral(base) {
                // Upper limit: align top of sup with top of integral's visible area
                // The integral container's top is the bbox top, but the glyph extends above
                // Place sup so its bottom aligns near the top of the bbox
                let supY = -supView.frame.height * 0.8
                supView.frame.origin = CGPoint(x: scriptX, y: supY)
            } else {
                let supY = -supView.frame.height * 0.5
                supView.frame.origin = CGPoint(x: scriptX, y: supY)
            }
            container.addSubview(supView)
            totalWidth = max(totalWidth, supView.frame.maxX)
            topExtension = max(0, -supView.frame.origin.y)
        }

        if let sub = sub {
            let subView = layoutRow(sub, fontSize: scriptFontSize)
            if isIntegral(base) {
                // Lower limit: align top of sub near bottom of bbox
                let subY = baseView.frame.height * 0.75
                subView.frame.origin = CGPoint(x: scriptX, y: subY)
            } else {
                let subY = baseView.frame.height * 0.6
                subView.frame.origin = CGPoint(x: scriptX, y: subY)
            }
            container.addSubview(subView)
            totalWidth = max(totalWidth, subView.frame.maxX)
            bottomExtension = max(0, subView.frame.maxY - baseView.frame.height)
        }

        if topExtension > 0 {
            for sub in container.subviews { sub.frame.origin.y += topExtension }
        }

        totalHeight += topExtension + bottomExtension
        container.frame = CGRect(x: 0, y: 0, width: totalWidth, height: totalHeight)
        // Baseline = base's baseline shifted by any top extension
        return (container, baseBaselineY + topExtension)
    }

    // MARK: - Delimited

    private func layoutDelimited(open: String, close: String, content: [MathNode], fontSize: CGFloat) -> (UIView, CGFloat) {
        let container = UIView()
        let contentView = layoutRow(content, fontSize: fontSize)
        let contentHeight = contentView.frame.height

        var x: CGFloat = 0

        if !open.isEmpty {
            let openLabel = makeDelimiterLabel(open, height: contentHeight, fontSize: fontSize)
            openLabel.frame.origin = CGPoint(x: x, y: (contentHeight - openLabel.frame.height) / 2)
            container.addSubview(openLabel)
            x += openLabel.frame.width + fontSize * 0.05
        }

        contentView.frame.origin = CGPoint(x: x, y: 0)
        container.addSubview(contentView)
        x += contentView.frame.width + fontSize * 0.05

        if !close.isEmpty {
            let closeLabel = makeDelimiterLabel(close, height: contentHeight, fontSize: fontSize)
            closeLabel.frame.origin = CGPoint(x: x, y: (contentHeight - closeLabel.frame.height) / 2)
            container.addSubview(closeLabel)
            x += closeLabel.frame.width
        }

        container.frame = CGRect(x: 0, y: 0, width: x, height: contentHeight)
        // Center aligns with math axis: reported baseline = center + mathAxisShift
        let mathAxisShift = fontSize * 0.32
        return (container, contentHeight / 2 + mathAxisShift)
    }

    /// Create a delimiter label scaled to match content height.
    private func makeDelimiterLabel(_ text: String, height: CGFloat, fontSize: CGFloat) -> UILabel {
        let label = UILabel()
        label.text = text
        // Scale font so delimiter matches content height
        let delimFontSize = max(fontSize, height * 0.85)
        label.font = mathFont(size: delimFontSize)
        label.textColor = .black
        label.tag = 9000 + charIndex
        charIndex += 1
        label.sizeToFit()
        return label
    }

    // MARK: - Matrix

    private func layoutMatrix(rows: [[[MathNode]]], open: String, close: String, fontSize: CGFloat) -> (UIView, CGFloat) {
        let cellPadding = fontSize * 0.2

        var cellViews: [[UIView]] = []
        var colWidths: [CGFloat] = []
        var rowHeights: [CGFloat] = []

        for row in rows {
            var rowViews: [UIView] = []
            var maxH: CGFloat = 0
            for (colIdx, cell) in row.enumerated() {
                let cellView = layoutRow(cell, fontSize: fontSize)
                rowViews.append(cellView)
                maxH = max(maxH, cellView.frame.height)
                if colIdx >= colWidths.count { colWidths.append(0) }
                colWidths[colIdx] = max(colWidths[colIdx], cellView.frame.width)
            }
            cellViews.append(rowViews)
            rowHeights.append(maxH)
        }

        let gridContainer = UIView()
        var y: CGFloat = 0
        for (rowIdx, rowViews) in cellViews.enumerated() {
            var x: CGFloat = 0
            for (colIdx, cellView) in rowViews.enumerated() {
                cellView.frame.origin = CGPoint(
                    x: x + (colWidths[colIdx] - cellView.frame.width) / 2,
                    y: y + (rowHeights[rowIdx] - cellView.frame.height) / 2
                )
                gridContainer.addSubview(cellView)
                x += colWidths[colIdx] + cellPadding
            }
            y += rowHeights[rowIdx] + cellPadding
        }

        let gridWidth = colWidths.reduce(0, +) + CGFloat(max(0, colWidths.count - 1)) * cellPadding
        let gridHeight = y - cellPadding
        gridContainer.frame = CGRect(x: 0, y: 0, width: gridWidth, height: gridHeight)

        if !open.isEmpty || !close.isEmpty {
            let wrapper = UIView()
            var wx: CGFloat = 0

            if !open.isEmpty {
                let openLabel = makeDelimiterLabel(open, height: gridHeight, fontSize: fontSize)
                openLabel.frame.origin = CGPoint(x: wx, y: (gridHeight - openLabel.frame.height) / 2)
                wrapper.addSubview(openLabel)
                wx += openLabel.frame.width + cellPadding * 0.5
            }

            gridContainer.frame.origin = CGPoint(x: wx, y: 0)
            wrapper.addSubview(gridContainer)
            wx += gridWidth + cellPadding * 0.5

            if !close.isEmpty {
                let closeLabel = makeDelimiterLabel(close, height: gridHeight, fontSize: fontSize)
                closeLabel.frame.origin = CGPoint(x: wx, y: (gridHeight - closeLabel.frame.height) / 2)
                wrapper.addSubview(closeLabel)
                wx += closeLabel.frame.width
            }

            wrapper.frame = CGRect(x: 0, y: 0, width: wx, height: gridHeight)
            let mathAxisShift = fontSize * 0.32
            return (wrapper, gridHeight / 2 + mathAxisShift)
        }

        let mathAxisShift = fontSize * 0.32
        return (gridContainer, gridHeight / 2 + mathAxisShift)
    }

    // MARK: - Character Collection

    /// Recursively compute the visual bounding rect of all subviews, including overflow from clipsToBounds=false.
    private func visualBounds(of view: UIView, relativeTo ancestor: UIView) -> CGRect {
        var rect = CGRect.null
        for sub in view.subviews {
            let subRect = sub.convert(sub.bounds, to: ancestor)
            rect = rect.union(subRect)
            // Recurse into children that may also overflow
            let childRect = visualBounds(of: sub, relativeTo: ancestor)
            if !childRect.isNull { rect = rect.union(childRect) }
        }
        return rect.isNull ? CGRect(origin: .zero, size: view.frame.size) : rect
    }

    private func collectCharacters(from view: UIView, relativeTo root: UIView, into chars: inout [OverlayCharacter]) {
        if view.tag >= 9000 {
            var rect = view.convert(view.bounds, to: root)
            let idx = view.tag - 9000
            let text: String
            if let label = view as? UILabel {
                text = label.text ?? ""
            } else {
                text = "—"
                // Ensure bar/line elements have visible bbox height
                if rect.height < 4 { rect = rect.insetBy(dx: 0, dy: -2) }
            }
            chars.append(OverlayCharacter(
                id: "c-\(idx)", index: idx, displayLatex: text, sourceToken: .latex, rect: rect
            ))
        }
        for sub in view.subviews {
            collectCharacters(from: sub, relativeTo: root, into: &chars)
        }
    }
}

// MARK: - Accent Shape View

/// Draws accent marks (hat, vec, dot, tilde) centered over content width using bezier paths.
private final class AccentShapeView: UIView {
    let symbol: String
    let contentWidth: CGFloat
    let accentFontSize: CGFloat

    init(symbol: String, width: CGFloat, fontSize: CGFloat) {
        self.symbol = symbol
        self.contentWidth = width
        self.accentFontSize = fontSize
        let height = fontSize * 0.12
        super.init(frame: CGRect(x: 0, y: 0, width: width, height: height))
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        let w = bounds.width
        let h = bounds.height
        let midX = w / 2
        let lineW: CGFloat = max(1.5, accentFontSize * 0.03)

        UIColor.black.setStroke()
        UIColor.black.setFill()

        switch symbol {
        case "→": // vector arrow — within bounds
            let path = UIBezierPath()
            let y = h * 0.5
            let arrowW = min(w * 0.8, accentFontSize * 0.5)
            let startX = midX - arrowW / 2
            let endX = midX + arrowW / 2
            path.move(to: CGPoint(x: startX, y: y))
            path.addLine(to: CGPoint(x: endX, y: y))
            let ah = h * 0.4
            path.move(to: CGPoint(x: endX - ah, y: y - ah))
            path.addLine(to: CGPoint(x: endX, y: y))
            path.addLine(to: CGPoint(x: endX - ah, y: y + ah))
            path.lineWidth = lineW
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()

        case "^": // hat — narrow pointed caret like LaTeX, within bounds
            let path = UIBezierPath()
            let hatW = min(w * 0.4, accentFontSize * 0.22)
            path.move(to: CGPoint(x: midX - hatW / 2, y: h * 0.95))
            path.addLine(to: CGPoint(x: midX, y: h * 0.05))
            path.addLine(to: CGPoint(x: midX + hatW / 2, y: h * 0.95))
            path.lineWidth = lineW * 0.8
            path.lineCapStyle = .round
            path.lineJoinStyle = .miter
            path.stroke()

        case "·": // dot — centered in view
            let dotR = max(2, accentFontSize * 0.05)
            let dotRect = CGRect(x: midX - dotR, y: h * 0.5 - dotR, width: dotR * 2, height: dotR * 2)
            UIBezierPath(ovalIn: dotRect).fill()

        case "··": // ddot — centered in view
            let dotR = max(2, accentFontSize * 0.05)
            let spacing = accentFontSize * 0.1
            let dot1 = CGRect(x: midX - spacing - dotR, y: h * 0.5 - dotR, width: dotR * 2, height: dotR * 2)
            let dot2 = CGRect(x: midX + spacing - dotR, y: h * 0.5 - dotR, width: dotR * 2, height: dotR * 2)
            UIBezierPath(ovalIn: dot1).fill()
            UIBezierPath(ovalIn: dot2).fill()

        case "~": // tilde — within bounds
            let path = UIBezierPath()
            let tildeW = min(w * 0.7, accentFontSize * 0.4)
            let startX = midX - tildeW / 2
            let endX = midX + tildeW / 2
            let y = h * 0.5
            let amp = h * 0.45
            path.move(to: CGPoint(x: startX, y: y + amp * 0.3))
            path.addCurve(
                to: CGPoint(x: endX, y: y - amp * 0.3),
                controlPoint1: CGPoint(x: startX + tildeW * 0.3, y: y - amp),
                controlPoint2: CGPoint(x: endX - tildeW * 0.3, y: y + amp)
            )
            path.lineWidth = lineW * 1.2
            path.lineCapStyle = .round
            path.stroke()

        default:
            break
        }
    }
}

// MARK: - Sqrt Shape View

private final class SqrtShapeView: UIView {
    let hookWidth: CGFloat
    let surdWidth: CGFloat
    let lineThickness: CGFloat

    init(frame: CGRect, hookWidth: CGFloat, surdWidth: CGFloat, lineThickness: CGFloat) {
        self.hookWidth = hookWidth
        self.surdWidth = surdWidth
        self.lineThickness = lineThickness
        super.init(frame: frame)
        isOpaque = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        let h = bounds.height
        let w = bounds.width

        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0, y: h * 0.6))
        path.addLine(to: CGPoint(x: hookWidth, y: h * 0.7))
        path.addLine(to: CGPoint(x: hookWidth + surdWidth, y: lineThickness / 2))
        path.addLine(to: CGPoint(x: w, y: lineThickness / 2))

        path.lineWidth = lineThickness
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        UIColor.black.setStroke()
        path.stroke()
    }
}
