#!/usr/bin/env swift
import Foundation

let SCRIPT_DIR = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let REPO = SCRIPT_DIR.deletingLastPathComponent()
let PARITY_JSON = REPO.appendingPathComponent("prototype/fixtures/routing_parity.json")
let WEIGHTS_JSON = REPO.appendingPathComponent("prototype/ocr_pipeline/models/router_weights.json")

struct ParityEntry: Decodable {
    let fixture: String
    let group_index: Int
    let content: String
    let confidence: Float
    let token_confidences: [Float]
    let route_ml: String
    let features_numeric: [Double]
    let features_layout: [Double]
    let strokes: [[[String: Float]]]
}

struct RouterWeights {
    let threshold: Double
    let bias: Double
    let ngramMin: Int
    let ngramMax: Int
    let vocabulary: [String: (idf: Double, weight: Double)]
    let numericWeights: [Double]
}

let latexCommandRe = try! NSRegularExpression(pattern: "\\\\[a-zA-Z]+")
let mathSymbolRe = try! NSRegularExpression(pattern: "[0-9+=^_/*<>()&-]")
let mathBracketRe = try! NSRegularExpression(pattern: "[\\[\\]:,|{}]")
let letterRunRe = try! NSRegularExpression(pattern: "[a-zA-Z]+")
let latexEnvRe = try! NSRegularExpression(pattern: "\\\\(?:begin|end)\\{[a-zA-Z*]+\\}")
let mathFuncRe = try! NSRegularExpression(
    pattern: "(?<![a-zA-Z])(?:arcsin|arccos|arctan|sqrt|sinh|cosh|tanh|log|ln|exp|sin|cos|tan|sec|csc|cot|lim|max|min|sup|inf|det|dim|deg|gcd|mod|arg)"
)

func longestLetterRun(_ content: String) -> Int {
    let range = NSRange(content.startIndex..., in: content)
    let s1 = latexEnvRe.stringByReplacingMatches(in: content, range: range, withTemplate: " ")
    let s2 = latexCommandRe.stringByReplacingMatches(in: s1, range: NSRange(s1.startIndex..., in: s1), withTemplate: " ")
    let s3 = mathFuncRe.stringByReplacingMatches(in: s2, range: NSRange(s2.startIndex..., in: s2), withTemplate: " ")
    let matches = letterRunRe.matches(in: s3, range: NSRange(s3.startIndex..., in: s3))
    var longest = 0
    for m in matches {
        longest = max(longest, m.range.length)
    }
    return longest
}

func fractionF(_ values: [Float], _ pred: (Float) -> Bool) -> Double {
    if values.isEmpty { return 0.0 }
    return Double(values.filter(pred).count) / Double(values.count)
}

func fractionC(_ s: String, _ pred: (Character) -> Bool) -> Double {
    if s.isEmpty { return 0.0 }
    return Double(s.filter(pred).count) / Double(s.count)
}

func quantile(_ sorted: [Float], _ q: Double) -> Double {
    let idx = min(sorted.count - 1, Int(q * Double(sorted.count)))
    return Double(sorted[idx])
}

let mathSymbolSet = CharacterSet(charactersIn: "0123456789+=^_/*<>()&-")
let mathBracketSet = CharacterSet(charactersIn: "[]{}:,|")

func routerFeatures(content: String, tokenConfidences: [Float]) -> [Double] {
    let confs = tokenConfidences.isEmpty ? [Float(0.0)] : tokenConfidences
    let ordered = confs.sorted()
    let mean = Double(confs.reduce(0, +)) / Double(confs.count)
    let variance = confs.reduce(0.0) { acc, v in acc + (Double(v) - mean) * (Double(v) - mean) } / Double(confs.count)
    let lettersOnly = latexCommandRe.stringByReplacingMatches(
        in: content, range: NSRange(content.startIndex..., in: content), withTemplate: " "
    )
    return [
        mean,
        Double(ordered[0]),
        variance.squareRoot(),
        quantile(ordered, 0.10),
        quantile(ordered, 0.25),
        quantile(ordered, 0.50),
        fractionF(confs) { $0 < 0.5 },
        fractionF(confs) { $0 < 0.9 },
        Double(min(longestLetterRun(content), 8)) / 8.0,
        fractionC(lettersOnly) { $0.isLetter },
        fractionC(lettersOnly) { $0.isNumber },
        fractionC(lettersOnly) { c in c.unicodeScalars.allSatisfy { mathSymbolSet.contains($0) } },
        fractionC(lettersOnly) { c in c.unicodeScalars.allSatisfy { mathBracketSet.contains($0) } },
        Double(latexCommandRe.numberOfMatches(in: content, range: NSRange(content.startIndex..., in: content))) / Double(confs.count),
        content.contains("=") ? 1.0 : 0.0,
        (content.contains("_") || content.contains("^")) ? 1.0 : 0.0,
        content.contains("\\frac") ? 1.0 : 0.0,
    ]
}

struct Pt { let x: Double; let y: Double }
struct Box { let minX: Double; let minY: Double; let maxX: Double; let maxY: Double
    var width: Double { maxX - minX }
    var height: Double { maxY - minY }
    var centerY: Double { (minY + maxY) / 2.0 }
    var centerX: Double { (minX + maxX) / 2.0 }
}

func strokeLayoutFeatures(_ strokes: [[[String: Float]]]) -> [Double] {
    var boxes: [Box] = []
    for stroke in strokes {
        if stroke.count < 2 { continue }
        var lo = Box(minX: Double(stroke[0]["x"]!), minY: Double(stroke[0]["y"]!),
                     maxX: Double(stroke[0]["x"]!), maxY: Double(stroke[0]["y"]!))
        for p in stroke.dropFirst() {
            lo = Box(minX: min(lo.minX, Double(p["x"]!)), minY: min(lo.minY, Double(p["y"]!)),
                     maxX: max(lo.maxX, Double(p["x"]!)), maxY: max(lo.maxY, Double(p["y"]!)))
        }
        boxes.append(lo)
    }
    if boxes.isEmpty { return Array(repeating: 0.0, count: 8) }
    boxes.sort { $0.centerX < $1.centerX }

    let widths = boxes.map { $0.width }
    let heights = boxes.map { $0.height }
    let centers = boxes.map { $0.centerY }

    let sortedH = heights.sorted()
    let medH: Double
    if sortedH.count % 2 == 0 {
        medH = (sortedH[sortedH.count / 2 - 1] + sortedH[sortedH.count / 2]) / 2.0
    } else {
        medH = sortedH[sortedH.count / 2]
    }
    let unit = medH != 0.0 ? medH : (heights.max() ?? 1.0)
    let safeUnit = unit != 0.0 ? unit : 1.0

    let meanC = centers.reduce(0, +) / Double(centers.count)
    let stdC = (centers.reduce(0.0) { $0 + ($1 - meanC) * ($1 - meanC) } / Double(centers.count)).squareRoot()

    let sortedC = centers.sorted()
    let medC: Double
    if sortedC.count % 2 == 0 {
        medC = (sortedC[sortedC.count / 2 - 1] + sortedC[sortedC.count / 2]) / 2.0
    } else {
        medC = sortedC[sortedC.count / 2]
    }
    let outlierFrac = Double(centers.filter { abs($0 - medC) > 0.5 * safeUnit }.count) / Double(centers.count)

    let steps: [Double] = centers.count > 1 ? zip(centers, centers.dropFirst()).map { abs($1 - $0) } : [0.0]
    let meanSteps = steps.reduce(0, +) / Double(steps.count)

    let overlapFrac: Double
    if widths.count > 1 {
        var ct = 0
        for i in 0 ..< boxes.count - 1 {
            let ov = min(boxes[i].maxX, boxes[i+1].maxX) - max(boxes[i].minX, boxes[i+1].minX)
            let sp = max(min(widths[i], widths[i+1]), 1e-9)
            if ov / sp > 0.5 { ct += 1 }
        }
        overlapFrac = Double(ct) / Double(widths.count - 1)
    } else {
        overlapFrac = 0.0
    }

    let maxW = widths.max() ?? 0.0
    let wideFrac = Double(zip(widths, heights).filter { $0 > 2.0 * max($1, 1e-9) }.count) / Double(widths.count)
    let meanH = heights.reduce(0, +) / Double(heights.count)
    let stdH = (heights.reduce(0.0) { $0 + ($1 - meanH) * ($1 - meanH) } / Double(heights.count)).squareRoot()
    let smallFrac = Double(heights.filter { $0 < 0.5 * safeUnit }.count) / Double(heights.count)

    return [
        stdC / safeUnit,
        outlierFrac,
        meanSteps / safeUnit,
        overlapFrac,
        min(maxW / safeUnit, 20.0) / 20.0,
        wideFrac,
        stdH / safeUnit,
        smallFrac,
    ]
}

func characterNgrams(_ content: String, low: Int, high: Int) -> [String] {
    var ngrams: [String] = []
    let words = content.lowercased().split(separator: " ")
    for word in words {
        let padded = " \(word) "
        let chars = Array(padded)
        for size in low ... high {
            if size > chars.count { break }
            for offset in 0 ... (chars.count - size) {
                ngrams.append(String(chars[offset ..< offset + size]))
            }
        }
    }
    return ngrams
}

func loadWeights() -> RouterWeights {
    let data = try! Data(contentsOf: WEIGHTS_JSON)
    let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    var vocab: [String: (idf: Double, weight: Double)] = [:]
    for (k, v) in json["vocabulary"] as! [String: [Double]] {
        vocab[k] = (idf: v[0], weight: v[1])
    }
    return RouterWeights(
        threshold: json["threshold"] as! Double,
        bias: json["bias"] as! Double,
        ngramMin: json["ngram_min"] as! Int,
        ngramMax: json["ngram_max"] as! Int,
        vocabulary: vocab,
        numericWeights: json["numeric_weights"] as! [Double]
    )
}

func routeGroup(weights: RouterWeights, content: String, tokenConfidences: [Float], strokes: [[[String: Float]]]) -> (String, Double) {
    let numeric = routerFeatures(content: content, tokenConfidences: tokenConfidences)
        + strokeLayoutFeatures(strokes)

    let ngrams = characterNgrams(content, low: weights.ngramMin, high: weights.ngramMax)
    var counts: [String: Int] = [:]
    for gram in ngrams {
        if weights.vocabulary[gram] != nil {
            counts[gram, default: 0] += 1
        }
    }
    var tfidf: [String: Double] = [:]
    for (gram, count) in counts {
        tfidf[gram] = (1.0 + log(Double(count))) * weights.vocabulary[gram]!.idf
    }
    let norm = {
        let s = tfidf.values.reduce(0.0) { $0 + $1 * $1 }.squareRoot()
        return s != 0.0 ? s : 1.0
    }()

    var total = weights.bias
    for (gram, value) in tfidf {
        total += (value / norm) * weights.vocabulary[gram]!.weight
    }
    for (i, value) in numeric.enumerated() {
        if i < weights.numericWeights.count {
            total += value * weights.numericWeights[i]
        }
    }
    let prob = 1.0 / (1.0 + exp(-total))
    let kind = prob >= weights.threshold ? "math" : "text"
    return (kind, prob)
}

let parityData = try! Data(contentsOf: PARITY_JSON)
let entries = try! JSONSerialization.jsonObject(with: parityData) as! [[String: Any]]
let weights = loadWeights()

print("=== Swift vs Python routing parity ===")
print("")

var mismatches = 0
for entry in entries {
    let fixture = entry["fixture"] as! String
    let groupIdx = entry["group_index"] as! Int
    let content = entry["content"] as! String
    let tokenConfs = (entry["token_confidences"] as! [Double]).map { Float($0) }
    let pythonRoute = entry["route_ml"] as! String
    let pythonNumeric = entry["features_numeric"] as! [Double]
    let pythonLayout = entry["features_layout"] as! [Double]
    let strokes = entry["strokes"] as! [[[String: Double]]]
    let strokesF = strokes.map { $0.map { d in
        var r: [String: Float] = [:]
        for (k, v) in d { r[k] = Float(v) }
        return r
    }}

    let swiftNumeric = routerFeatures(content: content, tokenConfidences: tokenConfs)
    let swiftLayout = strokeLayoutFeatures(strokesF)
    let (swiftRoute, prob) = routeGroup(weights: weights, content: content, tokenConfidences: tokenConfs, strokes: strokesF)

    let match = swiftRoute == pythonRoute ? "OK" : "MISMATCH"
    if swiftRoute != pythonRoute { mismatches += 1 }

    print("\(fixture) group \(groupIdx): '\(content)'")
    print("  python=\(pythonRoute)  swift=\(swiftRoute)  prob=\(String(format: "%.6f", prob))  [\(match)]")

    var featureDiffs: [String] = []
    for (i, (s, p)) in zip(swiftNumeric, pythonNumeric).enumerated() {
        if abs(s - p) > 1e-4 {
            featureDiffs.append("  numeric[\(i)]: swift=\(String(format: "%.6f", s)) python=\(String(format: "%.6f", p))")
        }
    }
    for (i, (s, p)) in zip(swiftLayout, pythonLayout).enumerated() {
        if abs(s - p) > 1e-4 {
            featureDiffs.append("  layout[\(i)]: swift=\(String(format: "%.6f", s)) python=\(String(format: "%.6f", p))")
        }
    }
    if !featureDiffs.isEmpty {
        print("  FEATURE DIFFS:")
        for d in featureDiffs { print(d) }
    }
    print("")
}

print("Total: \(entries.count) groups, \(mismatches) mismatches")
