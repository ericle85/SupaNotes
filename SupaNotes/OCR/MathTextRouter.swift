import Foundation

struct RouterWeights {
    let threshold: Double
    let bias: Double
    let ngramMin: Int
    let ngramMax: Int
    let vocabulary: [String: (idf: Double, weight: Double)]
    let numericWeights: [Double]
}

private var cachedWeights: RouterWeights?

func loadRouterWeights() -> RouterWeights? {
    if let cached = cachedWeights {
        return cached
    }
    guard let url = Bundle.main.url(forResource: "router_weights", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        return nil
    }

    let threshold = json["threshold"] as? Double ?? 0.575
    let bias = json["bias"] as? Double ?? 0.0
    let ngramMin = json["ngram_min"] as? Int ?? 1
    let ngramMax = json["ngram_max"] as? Int ?? 4
    let numericWeights = json["numeric_weights"] as? [Double] ?? []

    var vocabulary: [String: (idf: Double, weight: Double)] = [:]
    if let vocabDict = json["vocabulary"] as? [String: [Double]] {
        for (key, values) in vocabDict {
            if values.count >= 2 {
                vocabulary[key] = (idf: values[0], weight: values[1])
            }
        }
    }

    let weights = RouterWeights(
        threshold: threshold,
        bias: bias,
        ngramMin: ngramMin,
        ngramMax: ngramMax,
        vocabulary: vocabulary,
        numericWeights: numericWeights
    )
    cachedWeights = weights
    return weights
}

private func characterNgrams(_ content: String, low: Int, high: Int) -> [String] {
    var ngrams: [String] = []
    let words = content.lowercased().split(separator: " ")
    for word in words {
        let padded = " \(word) "
        let chars = Array(padded)
        for size in low ... high {
            if size > chars.count {
                break
            }
            for offset in 0 ... (chars.count - size) {
                ngrams.append(String(chars[offset ..< offset + size]))
            }
        }
    }
    return ngrams
}

private func fraction(_ items: String, _ predicate: (Character) -> Bool) -> Double {
    if items.isEmpty { return 0.0 }
    let count = Double(items.count)
    let matching = Double(items.filter(predicate).count)
    return matching / count
}

private func fractionFloats(_ values: [Float], _ predicate: (Float) -> Bool) -> Double {
    if values.isEmpty { return 0.0 }
    let count = Double(values.count)
    let matching = Double(values.filter(predicate).count)
    return matching / count
}

private func quantile(_ sorted: [Float], _ q: Double) -> Double {
    let idx = min(sorted.count - 1, Int(q * Double(sorted.count)))
    return Double(sorted[idx])
}

private let mathSymbolCharset = CharacterSet(charactersIn: "0123456789+=^_/*<>()&-")
private let mathBracketCharset = CharacterSet(charactersIn: "[]{}:,|")

func routerFeatures(content: String, tokenConfidences: [Float]) -> [Double] {
    let confidences = tokenConfidences.isEmpty ? [Float(0.0)] : tokenConfidences
    let ordered = confidences.sorted()
    let mean = Double(confidences.reduce(0, +)) / Double(confidences.count)
    let variance = confidences.reduce(0.0) { acc, v in acc + (Double(v) - mean) * (Double(v) - mean) } / Double(confidences.count)

    let lettersOnly = latexCommandPattern.stringByReplacingMatches(
        in: content,
        range: NSRange(content.startIndex..., in: content),
        withTemplate: " "
    )

    return [
        mean,
        Double(ordered[0]),
        variance.squareRoot(),
        quantile(ordered, 0.10),
        quantile(ordered, 0.25),
        quantile(ordered, 0.50),
        fractionFloats(confidences) { $0 < 0.5 },
        fractionFloats(confidences) { $0 < 0.9 },
        Double(min(longestLetterRun(content), 8)) / 8.0,
        fraction(lettersOnly) { $0.isLetter },
        fraction(lettersOnly) { $0.isNumber },
        fraction(lettersOnly) { char in
            char.unicodeScalars.allSatisfy { mathSymbolCharset.contains($0) }
        },
        fraction(lettersOnly) { char in
            char.unicodeScalars.allSatisfy { mathBracketCharset.contains($0) }
        },
        Double(latexCommandPattern.numberOfMatches(in: content, range: NSRange(content.startIndex..., in: content))) / Double(confidences.count),
        content.contains("=") ? 1.0 : 0.0,
        (content.contains("_") || content.contains("^")) ? 1.0 : 0.0,
        content.contains("\\frac") ? 1.0 : 0.0,
    ]
}

struct StrokeBox {
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double

    var width: Double { maxX - minX }
    var height: Double { maxY - minY }
    var centerY: Double { (minY + maxY) / 2.0 }
    var centerX: Double { (minX + maxX) / 2.0 }
}

private func strokeBoxesForRouter(_ strokes: [[CTCPoint]]) -> [StrokeBox]? {
    let boxes: [StrokeBox] = strokes.compactMap { stroke in
        if stroke.count < 2 { return nil }
        var lo = StrokeBox(minX: Double(stroke[0].x), minY: Double(stroke[0].y), maxX: Double(stroke[0].x), maxY: Double(stroke[0].y))
        for p in stroke.dropFirst() {
            lo.minX = min(lo.minX, Double(p.x))
            lo.minY = min(lo.minY, Double(p.y))
            lo.maxX = max(lo.maxX, Double(p.x))
            lo.maxY = max(lo.maxY, Double(p.y))
        }
        return lo
    }
    if boxes.isEmpty { return nil }
    return boxes.sorted { $0.centerX < $1.centerX }
}

func strokeLayoutFeatures(_ strokes: [[CTCPoint]]) -> [Double] {
    guard let boxes = strokeBoxesForRouter(strokes) else {
        return Array(repeating: 0.0, count: 8)
    }

    let widths = boxes.map { $0.width }
    let heights = boxes.map { $0.height }
    let centers = boxes.map { $0.centerY }

    let sortedHeights = heights.sorted()
    let medianHeight: Double
    if sortedHeights.count % 2 == 0 {
        medianHeight = (sortedHeights[sortedHeights.count / 2 - 1] + sortedHeights[sortedHeights.count / 2]) / 2.0
    } else {
        medianHeight = sortedHeights[sortedHeights.count / 2]
    }
    let unit = medianHeight != 0.0 ? medianHeight : (heights.max() ?? 1.0)
    let safeUnit = unit != 0.0 ? unit : 1.0

    let stdCenters: Double = {
        let mean = centers.reduce(0, +) / Double(centers.count)
        let variance = centers.reduce(0.0) { acc, v in acc + (v - mean) * (v - mean) } / Double(centers.count)
        return variance.squareRoot()
    }()

    let sortedCenters = centers.sorted()
    let medianCenter: Double
    if sortedCenters.count % 2 == 0 {
        medianCenter = (sortedCenters[sortedCenters.count / 2 - 1] + sortedCenters[sortedCenters.count / 2]) / 2.0
    } else {
        medianCenter = sortedCenters[sortedCenters.count / 2]
    }

    let outlierFraction = Double(centers.filter { abs($0 - medianCenter) > 0.5 * safeUnit }.count) / Double(centers.count)

    let steps: [Double]
    if centers.count > 1 {
        steps = zip(centers, centers.dropFirst()).map { abs($1 - $0) }
    } else {
        steps = [0.0]
    }
    let meanSteps = steps.reduce(0, +) / Double(steps.count)

    let overlapFraction: Double
    if widths.count > 1 {
        var overlapCount = 0
        for i in 0 ..< boxes.count - 1 {
            let overlap = min(boxes[i].maxX, boxes[i + 1].maxX) - max(boxes[i].minX, boxes[i + 1].minX)
            let span = max(min(widths[i], widths[i + 1]), 1e-9)
            if overlap / span > 0.5 {
                overlapCount += 1
            }
        }
        overlapFraction = Double(overlapCount) / Double(widths.count - 1)
    } else {
        overlapFraction = 0.0
    }

    let maxWidth = widths.max() ?? 0.0

    let wideMeanFraction = Double(zip(widths, heights).filter { w, h in w > 2.0 * max(h, 1e-9) }.count) / Double(widths.count)

    let stdHeights: Double = {
        let mean = heights.reduce(0, +) / Double(heights.count)
        let variance = heights.reduce(0.0) { acc, v in acc + (v - mean) * (v - mean) } / Double(heights.count)
        return variance.squareRoot()
    }()

    let smallHeightFraction = Double(heights.filter { $0 < 0.5 * safeUnit }.count) / Double(heights.count)

    return [
        stdCenters / safeUnit,
        outlierFraction,
        meanSteps / safeUnit,
        overlapFraction,
        min(maxWidth / safeUnit, 20.0) / 20.0,
        wideMeanFraction,
        stdHeights / safeUnit,
        smallHeightFraction,
    ]
}

func routeGroup(content: String, tokenConfidences: [Float], strokes: [[CTCPoint]]) -> RecognizedKind {
    guard let weights = loadRouterWeights() else {
        let mean = tokenConfidences.isEmpty ? Float(0.0) : tokenConfidences.reduce(0, +) / Float(tokenConfidences.count)
        return routeKind(content: content, confidence: mean)
    }

    let numeric = routerFeatures(content: content, tokenConfidences: tokenConfidences)
        + strokeLayoutFeatures(strokes)

    let ngrams = characterNgrams(content, low: weights.ngramMin, high: weights.ngramMax)

    var counts: [String: Int] = [:]
    for gram in ngrams {
        if weights.vocabulary[gram] != nil {
            counts[gram, default: 0] += 1
        }
    }

    var tfidfValues: [String: Double] = [:]
    for (gram, count) in counts {
        let idf = weights.vocabulary[gram]!.idf
        tfidfValues[gram] = (1.0 + log(Double(count))) * idf
    }

    let norm = {
        let sumSq = tfidfValues.values.reduce(0.0) { $0 + $1 * $1 }
        let n = sumSq.squareRoot()
        return n != 0.0 ? n : 1.0
    }()

    var total = weights.bias
    for (gram, value) in tfidfValues {
        total += (value / norm) * weights.vocabulary[gram]!.weight
    }
    for (i, value) in numeric.enumerated() {
        if i < weights.numericWeights.count {
            total += value * weights.numericWeights[i]
        }
    }

    let probability = 1.0 / (1.0 + exp(-total))
    return probability >= weights.threshold ? .math : .text
}
