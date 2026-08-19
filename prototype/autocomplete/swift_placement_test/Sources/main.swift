import Foundation

struct StrokeBounds {
    let minX: Double
    let maxX: Double
    let minY: Double
    let maxY: Double

    var width: Double { maxX - minX }
    var height: Double { maxY - minY }
    var midX: Double { (minX + maxX) / 2 }
    var midY: Double { (minY + maxY) / 2 }
}

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

func computeStrokeBounds(_ points: [Point]) -> StrokeBounds {
    let xs = points.map(\.x)
    let ys = points.map(\.y)
    return StrokeBounds(
        minX: xs.min()!,
        maxX: xs.max()!,
        minY: ys.min()!,
        maxY: ys.max()!
    )
}

func computeOverallBBox(strokes: [[Point]]) -> StrokeBounds {
    let allPoints = strokes.flatMap { $0 }
    return computeStrokeBounds(allPoints)
}

func findEqualSignCenter(strokes: [[Point]]) -> (x: Double, y: Double)? {
    var horizontals: [(midX: Double, midY: Double)] = []

    for stroke in strokes {
        let bounds = computeStrokeBounds(stroke)
        let xRange = bounds.width
        let yRange = bounds.height
        if xRange > 3.0 && yRange / (xRange + 0.01) < 0.4 {
            horizontals.append((midX: bounds.midX, midY: bounds.midY))
        }
    }

    for i in 0..<horizontals.count {
        for j in (i + 1)..<horizontals.count {
            let a = horizontals[i]
            let b = horizontals[j]
            let xDist = abs(a.midX - b.midX)
            let yDist = abs(a.midY - b.midY)
            if xDist < 10.0 && yDist > 2.0 && yDist < 12.0 {
                return ((a.midX + b.midX) / 2, (a.midY + b.midY) / 2)
            }
        }
    }

    return nil
}

func computeSuggestionPosition(
    bbox: StrokeBounds,
    mode: String,
    strokes: [[Point]]
) -> (x: Double, y: Double)? {
    let gap = 8.0
    let lineHeight = bbox.height

    if mode == "append" {
        return (bbox.maxX + gap, bbox.midY)
    }

    if mode == "below" {
        return (bbox.minX, bbox.maxY + lineHeight * 0.5)
    }

    if mode == "alignWithEqualSignAbove" {
        let equalX = findEqualSignCenter(strokes: strokes)?.x ?? bbox.minX
        return (equalX, bbox.maxY + lineHeight * 0.5)
    }

    return nil
}

let tolerance = 0.5

func testAppend(strokes: [[Point]], pipeline: [String: Any]) -> (Bool, String) {
    let bbox = computeOverallBBox(strokes: strokes)
    guard let placement = computeSuggestionPosition(bbox: bbox, mode: "append", strokes: strokes) else {
        return (false, "no placement returned")
    }

    if placement.x <= bbox.maxX {
        return (false, "x=\(String(format: "%.1f", placement.x)) not past bbox max_x=\(String(format: "%.1f", bbox.maxX))")
    }

    let midY = bbox.midY
    if abs(placement.y - midY) > tolerance {
        return (false, "y=\(String(format: "%.1f", placement.y)) not centered (expected \(String(format: "%.1f", midY)))")
    }

    return (true, "x=\(String(format: "%.1f", placement.x)), y=\(String(format: "%.1f", placement.y))")
}

func testAlignWithEqualSign(strokes: [[Point]], pipeline: [String: Any]) -> (Bool, String) {
    let bbox = computeOverallBBox(strokes: strokes)
    guard let eqCenter = findEqualSignCenter(strokes: strokes) else {
        return (false, "no equal sign found in strokes")
    }

    guard let placement = computeSuggestionPosition(
        bbox: bbox,
        mode: "alignWithEqualSignAbove",
        strokes: strokes
    ) else {
        return (false, "no placement returned")
    }

    if abs(placement.x - eqCenter.x) > tolerance {
        return (false, "placement x=\(String(format: "%.1f", placement.x)) != equal sign x=\(String(format: "%.1f", eqCenter.x))")
    }

    return (true, "eq_center=(\(String(format: "%.1f", eqCenter.x)),\(String(format: "%.1f", eqCenter.y))), placement=(\(String(format: "%.1f", placement.x)),\(String(format: "%.1f", placement.y)))")
}

let strokesDir: String
if CommandLine.arguments.count > 1 {
    strokesDir = CommandLine.arguments[1]
} else {
    strokesDir = NSString(string: "~/Downloads/strokes_exported").expandingTildeInPath
}

let fm = FileManager.default
guard let entries = try? fm.contentsOfDirectory(atPath: strokesDir) else {
    print("Cannot read \(strokesDir)")
    exit(1)
}

let folders = entries.filter {
    var isDir: ObjCBool = false
    fm.fileExists(atPath: "\(strokesDir)/\($0)", isDirectory: &isDir)
    return isDir.boolValue
}.sorted()

var passed = 0
var failed = 0

for folder in folders {
    let folderPath = "\(strokesDir)/\(folder)"
    let inkmlPath = "\(folderPath)/strokes.inkml"
    let pipelinePath = "\(folderPath)/pipeline_output.json"

    let strokes = parseInkML(path: inkmlPath)
    guard let pipelineData = fm.contents(atPath: pipelinePath),
          let pipeline = try? JSONSerialization.jsonObject(with: pipelineData) as? [String: Any] else {
        print("  SKIP  \(folder) (cannot read pipeline_output.json)")
        continue
    }

    let mode = pipeline["placement"] as? String ?? ""
    let suggestion = pipeline["suggestion"] as? String ?? ""

    let result: (Bool, String)
    switch mode {
    case "append":
        result = testAppend(strokes: strokes, pipeline: pipeline)
    case "alignWithEqualSignAbove":
        result = testAlignWithEqualSign(strokes: strokes, pipeline: pipeline)
    default:
        print("  SKIP  \(folder) (unknown mode: \(mode))")
        continue
    }

    let status = result.0 ? "PASS" : "FAIL"
    if result.0 {
        passed += 1
    } else {
        failed += 1
    }
    print("  \(status)  \(folder)  mode=\(mode)  suggestion='\(suggestion)'  \(result.1)")
}

print("\n\(passed) passed, \(failed) failed, \(folders.count) total")
exit(failed == 0 ? 0 : 1)
