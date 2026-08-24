import Foundation
import PencilKit

func exportStrokesToInkML(_ strokes: [PKStroke]) -> String {
    var xml = "<ink xmlns=\"http://www.w3.org/2003/InkML\">\n"
    xml += "  <traceFormat>\n"
    xml += "    <channel name=\"X\" type=\"decimal\" />\n"
    xml += "    <channel name=\"Y\" type=\"decimal\" />\n"
    xml += "    <channel name=\"T\" type=\"decimal\" units=\"ms\" />\n"
    xml += "  </traceFormat>\n"

    for (i, stroke) in strokes.enumerated() {
        let path = stroke.path
        if path.count < 2 {
            continue
        }

        var pointStrings = [String]()
        pointStrings.reserveCapacity(path.count)

        for j in 0 ..< path.count {
            let point = path[j]
            let x = String(format: "%.2f", point.location.x)
            let y = String(format: "%.2f", point.location.y)
            let t = String(format: "%.1f", point.timeOffset * 1000)
            pointStrings.append("\(x) \(y) \(t)")
        }

        xml += "  <trace id=\"\(i)\">"
        xml += pointStrings.joined(separator: ",")
        xml += "</trace>\n"
    }

    xml += "</ink>"
    return xml
}

func exportStrokeBundle(strokes: [PKStroke]) -> URL? {
    let timestamp = Int(Date().timeIntervalSince1970)
    let folderName = "strokes_\(timestamp)"
    let folderURL = FileManager.default.temporaryDirectory.appendingPathComponent(folderName)

    do {
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let inkml = exportStrokesToInkML(strokes)
        let inkmlURL = folderURL.appendingPathComponent("strokes.inkml")
        try inkml.write(to: inkmlURL, atomically: true, encoding: .utf8)

        return folderURL
    } catch {
        print("[InkMLExporter] Failed to write bundle: \(error)")
        return nil
    }
}
