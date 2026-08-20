import CoreGraphics
import Foundation

struct Point {
    let x: Double
    let y: Double
}

func parseInkML(path: String) -> [[Point]] {
    guard let data = FileManager.default.contents(atPath: path),
          let xml = try? XMLDocument(data: data, options: []) else {
        return []
    }
    guard let traces = try? xml.nodes(forXPath: "//*[local-name()='trace']") as? [XMLElement] else {
        return []
    }
    var strokes: [[Point]] = []
    for trace in traces {
        guard let text = trace.stringValue else { continue }
        var points: [Point] = []
        for ptStr in text.split(separator: ",") {
            let vals = ptStr.trimmingCharacters(in: .whitespaces).split(separator: " ")
            if vals.count >= 2,
               let x = Double(vals[0]),
               let y = Double(vals[1]) {
                points.append(Point(x: x, y: y))
            }
        }
        if points.count >= 2 {
            strokes.append(points)
        }
    }
    return strokes
}

func pointsToBounds(_ strokes: [[Point]]) -> [CGRect] {
    strokes.map { points in
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let minX = xs.min()!
        let minY = ys.min()!
        return CGRect(
            x: minX, y: minY,
            width: xs.max()! - minX,
            height: ys.max()! - minY
        )
    }
}

@main
enum PlacementCLI {
    static func main() {
        guard CommandLine.arguments.count > 1 else {
            print("Usage: placement_cli <inkml_path>")
            exit(1)
        }

        let inkmlPath = CommandLine.arguments[1]
        let strokes = parseInkML(path: inkmlPath)
        let bounds = pointsToBounds(strokes)
        let bbox = bounds.reduce(CGRect.null) { $0.union($1) }

        var output: [String: Any] = [:]

        if let center = findEqualSignCenter(strokeBounds: bounds) {
            output["equal_sign_center"] = ["x": round(center.x * 100) / 100, "y": round(center.y * 100) / 100]
        } else {
            output["equal_sign_center"] = NSNull()
        }

        let height = estimateStrokeHeight(strokeBounds: bounds)
        output["stroke_height"] = round(height * 100) / 100

        for mode in ["append", "below", "alignWithEqualSignAbove"] {
            if let pos = computeSuggestionPosition(bbox: bbox, mode: mode, strokeBounds: bounds) {
                output["position_\(mode)"] = ["x": round(pos.x * 100) / 100, "y": round(pos.y * 100) / 100]
            } else {
                output["position_\(mode)"] = NSNull()
            }
        }

        let jsonData = try! JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
        print(String(data: jsonData, encoding: .utf8)!)
    }
}
