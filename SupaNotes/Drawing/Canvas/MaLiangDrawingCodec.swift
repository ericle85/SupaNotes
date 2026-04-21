import UIKit

enum MaLiangDrawingCodec {
    static func encode(canvas: Canvas) throws -> Data {
        canvas.data.finishCurrentElement()
        let content = CanvasContent(
            size: canvas.size,
            lineStrips: canvas.data.elements.compactMap { $0 as? LineStrip },
            chartlets: canvas.data.elements.compactMap { $0 as? Chartlet }
        )
        return try JSONEncoder().encode(content)
    }

    static func decode(_ data: Data, into canvas: SupaCanvasView) {
        guard !data.isEmpty else {
            canvas.resetData(redraw: true)
            return
        }

        do {
            let content = try JSONDecoder().decode(CanvasContent.self, from: data)
            let lineStrips = content.lineStrips.map { strip -> LineStrip in
                strip.brush = canvas.brush(named: strip.brushName)
                return strip
            }
            content.chartlets.forEach { $0.canvas = canvas }
            canvas.data.elements = (lineStrips + content.chartlets).sorted(by: { $0.index < $1.index })
            canvas.redraw()
        } catch {
            canvas.resetData(redraw: true)
        }
    }

    static func decodeContent(_ data: Data) -> CanvasContent? {
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(CanvasContent.self, from: data)
    }
}

extension MLColor {
    var uiColor: UIColor {
        UIColor(
            red: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }
}
