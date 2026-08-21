import Foundation

func parseInkML(filePath: String) -> [[StrokePoint]] {
    guard let data = FileManager.default.contents(atPath: filePath),
          let xmlString = String(data: data, encoding: .utf8)
    else {
        print("[InkMLParser] Failed to read file: \(filePath)")
        return []
    }

    let parser = InkMLXMLParser(xmlString: xmlString)
    return parser.parse()
}

func parseInkMLFromBundle(resourceName: String) -> [[StrokePoint]] {
    guard let url = Bundle.main.url(forResource: resourceName, withExtension: "inkml") else {
        print("[InkMLParser] Resource not found: \(resourceName)")
        return []
    }
    return parseInkML(filePath: url.path)
}

private class InkMLXMLParser: NSObject, XMLParserDelegate {
    private let xmlString: String
    private var strokes: [[StrokePoint]] = []
    private var currentTraceText: String = ""
    private var insideTrace = false

    init(xmlString: String) {
        self.xmlString = xmlString
    }

    func parse() -> [[StrokePoint]] {
        guard let data = xmlString.data(using: .utf8) else {
            return []
        }
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return strokes
    }

    func parser(
        _: XMLParser, didStartElement elementName: String,
        namespaceURI _: String?, qualifiedName _: String?,
        attributes _: [String: String] = [:]
    ) {
        if elementName == "trace" {
            insideTrace = true
            currentTraceText = ""
        }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        if insideTrace {
            currentTraceText += string
        }
    }

    func parser(
        _: XMLParser, didEndElement elementName: String,
        namespaceURI _: String?, qualifiedName _: String?
    ) {
        if elementName == "trace" {
            insideTrace = false
            let points = parseTraceText(currentTraceText)
            if points.count >= 2 {
                strokes.append(points)
            }
        }
    }

    private func parseTraceText(_ text: String) -> [StrokePoint] {
        let pointStrings = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: ",")

        var points = [StrokePoint]()
        for ptStr in pointStrings {
            let vals = ptStr.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }

            if vals.count >= 3,
               let x = Float(vals[0]),
               let y = Float(vals[1]),
               let t = Float(vals[2])
            {
                points.append(StrokePoint(x: x, y: y, t: t))
            } else if vals.count >= 2,
                      let x = Float(vals[0]),
                      let y = Float(vals[1])
            {
                points.append(StrokePoint(x: x, y: y, t: 0.0))
            }
        }
        return points
    }
}
