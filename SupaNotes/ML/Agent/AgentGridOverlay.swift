import UIKit

/// Draws a labeled grid overlay on a page image and converts cell IDs back to rects.
struct AgentGridOverlay {
    let columns: Int
    let rows: Int

    init(columns: Int = 6, rows: Int = 10) {
        self.columns = columns
        self.rows = rows
    }

    // MARK: - Draw grid onto image

    func drawGrid(on image: UIImage) -> UIImage {
        let size = image.size
        let cellW = size.width / CGFloat(columns)
        let cellH = size.height / CGFloat(rows)

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            image.draw(at: .zero)

            let gc = ctx.cgContext

            // Grid lines — light gray dashes
            gc.setStrokeColor(UIColor.systemGray3.cgColor)
            gc.setLineWidth(1.0)
            gc.setLineDash(phase: 0, lengths: [4, 4])

            for col in 1..<columns {
                let x = CGFloat(col) * cellW
                gc.move(to: CGPoint(x: x, y: 0))
                gc.addLine(to: CGPoint(x: x, y: size.height))
            }
            for row in 1..<rows {
                let y = CGFloat(row) * cellH
                gc.move(to: CGPoint(x: 0, y: y))
                gc.addLine(to: CGPoint(x: size.width, y: y))
            }
            gc.strokePath()

            // Cell labels
            let fontSize = max(10, min(cellW, cellH) * 0.18)
            let font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.systemRed.withAlphaComponent(0.85)
            ]

            for row in 0..<rows {
                for col in 0..<columns {
                    let label = cellLabel(col: col, row: row)
                    let x = CGFloat(col) * cellW + 2
                    let y = CGFloat(row) * cellH + 1
                    (label as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
                }
            }
        }
    }

    // MARK: - Cell ID ↔ Coordinates

    /// Convert a cell label like "B3" to column, row indices.
    func parseCell(_ label: String) -> (col: Int, row: Int)? {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first,
              first.isUppercase,
              let asciiFirst = first.asciiValue,
              let asciiA = Character("A").asciiValue else { return nil }
        let col = Int(asciiFirst) - Int(asciiA)
        guard col >= 0, col < columns else { return nil }

        let rowStr = String(trimmed.dropFirst())
        guard let row = Int(rowStr), row >= 0, row < rows else { return nil }
        return (col, row)
    }

    /// Convert a cell ID to a rect in image space (pixels) for a given image size.
    func cellRect(label: String, imageSize: CGSize) -> CGRect? {
        guard let (col, row) = parseCell(label) else { return nil }
        let cellW = imageSize.width / CGFloat(columns)
        let cellH = imageSize.height / CGFloat(rows)
        return CGRect(
            x: CGFloat(col) * cellW,
            y: CGFloat(row) * cellH,
            width: cellW,
            height: cellH
        )
    }

    /// Merge an array of cell IDs into minimal bounding rects (connected components).
    func mergeOccupiedCells(_ labels: [String], imageSize: CGSize) -> [CGRect] {
        // Parse all valid cells into a set of (col, row)
        var occupied = Set<String>()
        var parsed: [(col: Int, row: Int)] = []
        for label in labels {
            guard let cell = parseCell(label) else { continue }
            let key = "\(cell.col),\(cell.row)"
            if occupied.insert(key).inserted {
                parsed.append(cell)
            }
        }
        guard !parsed.isEmpty else { return [] }

        // Flood-fill connected components (4-connected)
        var visited = Set<String>()
        var components: [[(col: Int, row: Int)]] = []

        for cell in parsed {
            let key = "\(cell.col),\(cell.row)"
            guard !visited.contains(key) else { continue }

            var component: [(col: Int, row: Int)] = []
            var queue = [cell]
            visited.insert(key)

            while !queue.isEmpty {
                let cur = queue.removeFirst()
                component.append(cur)

                for (dc, dr) in [(-1,0),(1,0),(0,-1),(0,1)] {
                    let nc = cur.col + dc
                    let nr = cur.row + dr
                    let nk = "\(nc),\(nr)"
                    guard occupied.contains(nk), !visited.contains(nk) else { continue }
                    visited.insert(nk)
                    queue.append((nc, nr))
                }
            }
            components.append(component)
        }

        // Convert each component to a bounding rect
        let cellW = imageSize.width / CGFloat(columns)
        let cellH = imageSize.height / CGFloat(rows)

        return components.map { cells in
            let minCol = cells.map(\.col).min()!
            let maxCol = cells.map(\.col).max()!
            let minRow = cells.map(\.row).min()!
            let maxRow = cells.map(\.row).max()!
            return CGRect(
                x: CGFloat(minCol) * cellW,
                y: CGFloat(minRow) * cellH,
                width: CGFloat(maxCol - minCol + 1) * cellW,
                height: CGFloat(maxRow - minRow + 1) * cellH
            )
        }
    }

    // MARK: - Cropping

    /// Crop a region from the original (non-gridded) image.
    func cropImage(_ image: UIImage, to rect: CGRect) -> UIImage? {
        let scale = image.scale
        let scaledRect = CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        guard let cgCrop = image.cgImage?.cropping(to: scaledRect) else { return nil }
        return UIImage(cgImage: cgCrop, scale: scale, orientation: image.imageOrientation)
    }

    // MARK: - Helpers

    private func cellLabel(col: Int, row: Int) -> String {
        let letter = String(UnicodeScalar(Int(("A" as UnicodeScalar).value) + col)!)
        return "\(letter)\(row)"
    }
}
