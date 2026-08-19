import Foundation

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
