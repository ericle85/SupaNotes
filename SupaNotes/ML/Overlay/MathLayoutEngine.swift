import UIKit

struct MathLayoutResult {
    let image: UIImage
    let size: CGSize
    let characters: [OverlayCharacter]
}

/// Lays out MathNodes as UIViews, extracts per-element bounding rects, renders to UIImage.
final class MathLayoutEngine {
    private let debugColors: [UIColor] = [.red, .blue, .green, .orange, .purple, .magenta, .cyan, .yellow]
    private var charIndex = 0

    func layout(nodes: [MathNode], fontSize: CGFloat, drawDebugBoxes: Bool = true) -> MathLayoutResult {
        charIndex = 0
        let root = UIView()
        root.backgroundColor = .clear

        let rowView = layoutRow(nodes, fontSize: fontSize)
        root.addSubview(rowView)

        let padding: CGFloat = 16
        let size = CGSize(width: rowView.frame.width + padding * 2, height: rowView.frame.height + padding * 2)
        rowView.frame.origin = CGPoint(x: padding, y: padding)
        root.frame = CGRect(origin: .zero, size: size)

        // Extract bounding rects
        var characters: [OverlayCharacter] = []
        collectCharacters(from: root, relativeTo: root, into: &characters)

        // Draw debug boxes
        if drawDebugBoxes {
            for char in characters {
                let box = UIView(frame: char.rect)
                box.backgroundColor = .clear
                box.layer.borderColor = debugColors[char.index % debugColors.count].cgColor
                box.layer.borderWidth = 2
                root.addSubview(box)
            }
        }

        // Render to image
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            root.layer.render(in: ctx.cgContext)
        }

        return MathLayoutResult(image: image, size: size, characters: characters)
    }

    // MARK: - Layout

    private func layoutRow(_ nodes: [MathNode], fontSize: CGFloat) -> UIView {
        let container = UIView()
        var x: CGFloat = 0
        var maxHeight: CGFloat = 0
        var subviews: [(UIView, CGFloat)] = [] // (view, baseline offset from center)

        for node in nodes {
            let (view, baselineOffset) = layoutNode(node, fontSize: fontSize)
            subviews.append((view, baselineOffset))
            maxHeight = max(maxHeight, view.frame.height)
        }

        // Position subviews horizontally, aligned by baseline
        let midY = maxHeight / 2
        for (view, baselineOffset) in subviews {
            let y = midY - view.frame.height / 2 + baselineOffset
            view.frame.origin = CGPoint(x: x, y: y)
            container.addSubview(view)
            x += view.frame.width + fontSize * 0.1 // small gap
        }

        container.frame = CGRect(x: 0, y: 0, width: x, height: maxHeight)
        return container
    }

    /// Returns (view, baselineOffset) where baselineOffset shifts the view relative to center.
    private func layoutNode(_ node: MathNode, fontSize: CGFloat) -> (UIView, CGFloat) {
        switch node {
        case .glyph(let text):
            return (makeGlyphLabel(text, fontSize: fontSize), 0)

        case .text(let text):
            return (makeTextView(text, fontSize: fontSize), 0)

        case .space:
            let spacer = UIView(frame: CGRect(x: 0, y: 0, width: fontSize * 0.3, height: fontSize))
            return (spacer, 0)

        case .fracLine:
            let line = makeFracLine(width: fontSize * 1.5, fontSize: fontSize)
            return (line, 0)

        case .fraction(let num, let den):
            return layoutFraction(num: num, den: den, fontSize: fontSize)

        case .script(let base, let sub, let sup):
            return layoutScript(base: base, sub: sub, sup: sup, fontSize: fontSize)

        case .delimited(let open, let close, let content):
            return layoutDelimited(open: open, close: close, content: content, fontSize: fontSize)

        case .matrix(let rows, let open, let close):
            return layoutMatrix(rows: rows, open: open, close: close, fontSize: fontSize)

        case .row(let nodes):
            return (layoutRow(nodes, fontSize: fontSize), 0)
        }
    }

    // MARK: - Glyph

    private func makeGlyphLabel(_ text: String, fontSize: CGFloat) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: fontSize)
        label.textColor = .black
        label.tag = 9000 + charIndex
        charIndex += 1
        label.sizeToFit()
        // Ensure minimum size for detection
        let minSize = fontSize * 0.8
        label.frame.size.width = max(label.frame.width, minSize)
        label.frame.size.height = max(label.frame.height, minSize)
        label.textAlignment = .center
        return label
    }

    private func makeTextView(_ text: String, fontSize: CGFloat) -> UIView {
        let container = UIView()
        var x: CGFloat = 0
        for ch in text {
            let label = UILabel()
            label.text = String(ch)
            label.font = UIFont.systemFont(ofSize: fontSize)
            label.textColor = .black
            label.tag = 9000 + charIndex
            charIndex += 1
            label.sizeToFit()
            let minSize = fontSize * 0.6
            label.frame.size.width = max(label.frame.width, minSize)
            label.frame.size.height = max(label.frame.height, fontSize)
            label.frame.origin = CGPoint(x: x, y: 0)
            container.addSubview(label)
            x += label.frame.width
        }
        container.frame = CGRect(x: 0, y: 0, width: x, height: fontSize * 1.2)
        return container
    }

    // MARK: - Fraction

    private func layoutFraction(num: [MathNode], den: [MathNode], fontSize: CGFloat) -> (UIView, CGFloat) {
        let container = UIView()
        let fracFontSize = fontSize * 0.75

        let numView = layoutRow(num, fontSize: fracFontSize)
        let denView = layoutRow(den, fontSize: fracFontSize)
        let lineWidth = max(numView.frame.width, denView.frame.width) + fontSize * 0.3
        let lineHeight: CGFloat = 2
        let gap: CGFloat = fontSize * 0.1

        // Fraction line (its own tracked element)
        let line = UIView()
        line.backgroundColor = .black
        line.tag = 9000 + charIndex
        charIndex += 1
        line.frame = CGRect(x: 0, y: numView.frame.height + gap, width: lineWidth, height: lineHeight)

        // Center numerator and denominator
        numView.frame.origin = CGPoint(x: (lineWidth - numView.frame.width) / 2, y: 0)
        denView.frame.origin = CGPoint(x: (lineWidth - denView.frame.width) / 2, y: line.frame.maxY + gap)

        container.addSubview(numView)
        container.addSubview(line)
        container.addSubview(denView)

        let totalHeight = denView.frame.maxY
        container.frame = CGRect(x: 0, y: 0, width: lineWidth, height: totalHeight)

        // Baseline offset: fraction line should be at vertical center
        let lineCenter = line.frame.midY
        let viewCenter = totalHeight / 2
        let baselineOffset = lineCenter - viewCenter

        return (container, baselineOffset)
    }

    private func makeFracLine(width: CGFloat, fontSize: CGFloat) -> UIView {
        let line = UIView()
        line.backgroundColor = .black
        line.tag = 9000 + charIndex
        charIndex += 1
        line.frame = CGRect(x: 0, y: 0, width: width, height: 2)
        return line
    }

    // MARK: - Script (sub/superscript)

    private func layoutScript(base: MathNode, sub: [MathNode]?, sup: [MathNode]?, fontSize: CGFloat) -> (UIView, CGFloat) {
        let container = UIView()
        let scriptFontSize = fontSize * 0.6

        let (baseView, baseOffset) = layoutNode(base, fontSize: fontSize)
        container.addSubview(baseView)

        var totalWidth = baseView.frame.width
        var totalHeight = baseView.frame.height
        var topExtension: CGFloat = 0
        var bottomExtension: CGFloat = 0

        if let sup = sup {
            let supView = layoutRow(sup, fontSize: scriptFontSize)
            supView.frame.origin = CGPoint(
                x: baseView.frame.width + 2,
                y: -supView.frame.height * 0.3
            )
            container.addSubview(supView)
            totalWidth = max(totalWidth, supView.frame.maxX)
            topExtension = max(0, -supView.frame.minY)
        }

        if let sub = sub {
            let subView = layoutRow(sub, fontSize: scriptFontSize)
            subView.frame.origin = CGPoint(
                x: baseView.frame.width + 2,
                y: baseView.frame.height * 0.5
            )
            container.addSubview(subView)
            totalWidth = max(totalWidth, subView.frame.maxX)
            bottomExtension = max(0, subView.frame.maxY - baseView.frame.height)
        }

        // Shift everything down to account for superscript going above
        if topExtension > 0 {
            for sub in container.subviews {
                sub.frame.origin.y += topExtension
            }
        }

        totalHeight = totalHeight + topExtension + bottomExtension
        container.frame = CGRect(x: 0, y: 0, width: totalWidth, height: totalHeight)
        return (container, baseOffset)
    }

    // MARK: - Delimited

    private func layoutDelimited(open: String, close: String, content: [MathNode], fontSize: CGFloat) -> (UIView, CGFloat) {
        let container = UIView()
        let contentView = layoutRow(content, fontSize: fontSize)
        let contentHeight = contentView.frame.height
        let delimFontSize = contentHeight * 0.9

        var x: CGFloat = 0

        // Open delimiter
        let openLabel = UILabel()
        openLabel.text = open
        openLabel.font = UIFont.systemFont(ofSize: delimFontSize)
        openLabel.textColor = .black
        openLabel.tag = 9000 + charIndex
        charIndex += 1
        openLabel.sizeToFit()
        openLabel.frame.origin = CGPoint(x: x, y: (contentHeight - openLabel.frame.height) / 2)
        container.addSubview(openLabel)
        x += openLabel.frame.width + fontSize * 0.1

        // Content
        contentView.frame.origin = CGPoint(x: x, y: 0)
        container.addSubview(contentView)
        x += contentView.frame.width + fontSize * 0.1

        // Close delimiter
        let closeLabel = UILabel()
        closeLabel.text = close
        closeLabel.font = UIFont.systemFont(ofSize: delimFontSize)
        closeLabel.textColor = .black
        closeLabel.tag = 9000 + charIndex
        charIndex += 1
        closeLabel.sizeToFit()
        closeLabel.frame.origin = CGPoint(x: x, y: (contentHeight - closeLabel.frame.height) / 2)
        container.addSubview(closeLabel)
        x += closeLabel.frame.width

        container.frame = CGRect(x: 0, y: 0, width: x, height: contentHeight)
        return (container, 0)
    }

    // MARK: - Matrix

    private func layoutMatrix(rows: [[[MathNode]]], open: String, close: String, fontSize: CGFloat) -> (UIView, CGFloat) {
        let container = UIView()
        let cellPadding = fontSize * 0.3

        // Layout each cell
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

        // Position cells in grid
        let gridContainer = UIView()
        var y: CGFloat = 0
        for (rowIdx, rowViews) in cellViews.enumerated() {
            var x: CGFloat = 0
            for (colIdx, cellView) in rowViews.enumerated() {
                let cx = x + (colWidths[colIdx] - cellView.frame.width) / 2
                let cy = y + (rowHeights[rowIdx] - cellView.frame.height) / 2
                cellView.frame.origin = CGPoint(x: cx, y: cy)
                gridContainer.addSubview(cellView)
                x += colWidths[colIdx] + cellPadding
            }
            y += rowHeights[rowIdx] + cellPadding
        }

        let gridWidth = colWidths.reduce(0, +) + CGFloat(max(0, colWidths.count - 1)) * cellPadding
        let gridHeight = y - cellPadding
        gridContainer.frame = CGRect(x: 0, y: 0, width: gridWidth, height: gridHeight)

        // Wrap in delimiters
        if !open.isEmpty || !close.isEmpty {
            let result = layoutDelimited(open: open, close: close, content: [.row([])], fontSize: fontSize)
            // Replace content with actual grid
            let wrapper = UIView()
            var wx: CGFloat = 0

            if !open.isEmpty {
                let delimFontSize = gridHeight * 0.9
                let openLabel = UILabel()
                openLabel.text = open
                openLabel.font = UIFont.systemFont(ofSize: delimFontSize)
                openLabel.textColor = .black
                openLabel.tag = 9000 + charIndex
                charIndex += 1
                openLabel.sizeToFit()
                openLabel.frame.origin = CGPoint(x: wx, y: (gridHeight - openLabel.frame.height) / 2)
                wrapper.addSubview(openLabel)
                wx += openLabel.frame.width + cellPadding
            }

            gridContainer.frame.origin = CGPoint(x: wx, y: 0)
            wrapper.addSubview(gridContainer)
            wx += gridWidth + cellPadding

            if !close.isEmpty {
                let delimFontSize = gridHeight * 0.9
                let closeLabel = UILabel()
                closeLabel.text = close
                closeLabel.font = UIFont.systemFont(ofSize: delimFontSize)
                closeLabel.textColor = .black
                closeLabel.tag = 9000 + charIndex
                charIndex += 1
                closeLabel.sizeToFit()
                closeLabel.frame.origin = CGPoint(x: wx, y: (gridHeight - closeLabel.frame.height) / 2)
                wrapper.addSubview(closeLabel)
                wx += closeLabel.frame.width
            }

            wrapper.frame = CGRect(x: 0, y: 0, width: wx, height: gridHeight)
            _ = result // suppress unused warning
            return (wrapper, 0)
        }

        return (gridContainer, 0)
    }

    // MARK: - Character Collection

    private func collectCharacters(from view: UIView, relativeTo root: UIView, into chars: inout [OverlayCharacter]) {
        if view.tag >= 9000 {
            let rect = view.convert(view.bounds, to: root)
            let idx = view.tag - 9000
            let text: String
            if let label = view as? UILabel {
                text = label.text ?? ""
            } else {
                text = "—" // fraction line
            }
            chars.append(OverlayCharacter(
                id: "c-\(idx)",
                index: idx,
                displayLatex: text,
                sourceToken: .latex,
                rect: rect
            ))
        }
        for sub in view.subviews {
            collectCharacters(from: sub, relativeTo: root, into: &chars)
        }
    }
}
