import Foundation

/// Parses gemma4's non-JSON tool call formats when Ollama's parser fails.
/// Handles: `call:funcname{a=1,b=2}`, `call:Math.abs{-7}`, `call:tool:foo{a:5/6,b:1}`
func parseFallbackToolCalls(from content: String) -> [[String: Any]] {
    let pattern = #"call:([\w.:]+)\{([^}]*)\}"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(content.startIndex..., in: content)

    return regex.matches(in: content, range: range).compactMap { match -> [String: Any]? in
        guard let nameRange = Range(match.range(at: 1), in: content),
              let argsRange = Range(match.range(at: 2), in: content) else { return nil }

        var rawName = String(content[nameRange])
        if rawName.hasPrefix("tool:") { rawName = String(rawName.dropFirst(5)) }
        let name = rawName.contains(".") ? String(rawName.split(separator: ".").last ?? Substring(rawName)) : rawName
        guard name != "none", !name.isEmpty else { return nil }

        let argString = String(content[argsRange])
        var argsDict: [String: Double] = [:]

        for pair in argString.split(separator: ",") {
            let parts = pair.split(whereSeparator: { $0 == "=" || $0 == ":" })
            if parts.count == 2 {
                let key = String(parts[0].trimmingCharacters(in: .whitespaces))
                let rawVal = String(parts[1].trimmingCharacters(in: .whitespaces))
                if let val = Double(rawVal) { argsDict[key] = val }
                else if let val = parseFraction(rawVal) { argsDict[key] = val }
            } else if parts.count == 1 {
                let rawVal = String(pair.trimmingCharacters(in: .whitespaces))
                let key = argsDict.isEmpty ? "a" : "b"
                if let val = Double(rawVal) { argsDict[key] = val }
                else if let val = parseFraction(rawVal) { argsDict[key] = val }
            }
        }

        guard let argsData = try? JSONEncoder().encode(argsDict),
              let argsStr = String(data: argsData, encoding: .utf8) else { return nil }
        return ["function": ["name": name, "arguments": argsStr]]
    }
}

private func parseFraction(_ s: String) -> Double? {
    let parts = s.split(separator: "/")
    guard parts.count == 2,
          let num = Double(parts[0]),
          let den = Double(parts[1]),
          den != 0 else { return nil }
    return num / den
}
