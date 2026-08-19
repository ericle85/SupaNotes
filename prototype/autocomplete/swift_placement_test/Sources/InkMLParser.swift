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
    return parseTraces(traces)
}

func parseTraces(_ traces: [XMLElement]) -> [[Point]] {
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
