import Foundation

// MARK: - Types

public struct Tool: Codable {
    let type: String
    let function: ToolFunction
}

public struct ToolFunction: Codable {
    let name: String
    let description: String
    let parameters: ToolParameters
}

public struct ToolParameters: Codable {
    let type: String
    let properties: [String: PropertyDefinition]
    let required: [String]
}

public struct PropertyDefinition: Codable {
    let type: String
    let description: String
}

struct ToolCall: Codable {
    let id: String?
    let type: String?
    let function: FunctionCall
}

struct FunctionCall: Codable {
    let name: String
    let arguments: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        if let str = try? c.decode(String.self, forKey: .arguments) {
            arguments = str
        } else {
            let dict = try c.decode([String: AnyCodable].self, forKey: .arguments)
            arguments = String(data: try JSONEncoder().encode(dict), encoding: .utf8) ?? "{}"
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(arguments, forKey: .arguments)
    }

    private enum CodingKeys: String, CodingKey { case name, arguments }
}

struct AnyCodable: Codable {
    let value: Any

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { value = i }
        else if let d = try? c.decode(Double.self) { value = d }
        else if let s = try? c.decode(String.self) { value = s }
        else if let b = try? c.decode(Bool.self) { value = b }
        else { value = "" }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let i as Int:    try c.encode(i)
        case let d as Double: try c.encode(d)
        case let s as String: try c.encode(s)
        case let b as Bool:   try c.encode(b)
        default: try c.encode("")
        }
    }
}

// MARK: - Client

public final class AgentOllamaClient {
    private let host: String
    private let port: Int
    private let model: String

    /// Tool calls made during the last `suggest` invocation.
    public private(set) var toolCallLog: [String] = []
    public func clearLog() { toolCallLog = [] }

    private let availableTools: [Tool] = [
        mathTool("gcd",      "Greatest common divisor of two integers a and b."),
        mathTool("min",      "Minimum of two numbers a and b."),
        mathTool("max",      "Maximum of two numbers a and b."),
        mathTool("add",      "Add two numbers together. Use this for any addition operations."),
        mathTool("subtract", "Subtract b from a. Use this for any subtraction operations."),
        mathTool("multiply", "Multiply two numbers together. Use this for any multiplication operations."),
        mathTool("divide",   "Divide a by b. Use this for any division operations."),
        Tool(type: "function", function: ToolFunction(
            name: "abs", description: "Absolute value of a number.",
            parameters: ToolParameters(
                type: "object",
                properties: ["a": PropertyDefinition(type: "number", description: "Input number")],
                required: ["a"]
            )
        )),
        Tool(type: "function", function: ToolFunction(
            name: "solve_quadratic",
            description: "Solve ax^2 + bx + c = 0. Returns the real roots.",
            parameters: ToolParameters(
                type: "object",
                properties: [
                    "a": PropertyDefinition(type: "number", description: "Coefficient of x^2"),
                    "b": PropertyDefinition(type: "number", description: "Coefficient of x"),
                    "c": PropertyDefinition(type: "number", description: "Constant term")
                ],
                required: ["a", "b", "c"]
            )
        )),
        Tool(type: "function", function: ToolFunction(
            name: "floor", description: "Floor of a number — largest integer less than or equal to a.",
            parameters: ToolParameters(
                type: "object",
                properties: ["a": PropertyDefinition(type: "number", description: "Input number")],
                required: ["a"]
            )
        ))
    ]

    private let thinking: Bool

    public init(host: String = "100.121.248.31", port: Int = 11434, model: String = "gemma4:e2b-it-q4_K_M", thinking: Bool = true) {
        self.host = host
        self.port = port
        self.model = model
        self.thinking = thinking
    }

    /// Text-only path — no image needed. Used by tests.
    public func suggest(text ocrText: String, renderFeedback: [String] = []) async throws -> String {
        let hints = thinking ? [] : (try? await toolExtractionPass(ocrText: ocrText)) ?? []
        return try await chat(
            prompt: buildPrompt(ocrText: ocrText, renderFeedback: renderFeedback, toolHints: hints),
            imageBase64: nil,
            suppressTools: !hints.isEmpty
        )
    }

    /// Image path — pass raw PNG bytes. Caller owns UIImage → Data conversion.
    public func suggest(imagePNG: Data, renderFeedback: [String] = []) async throws -> String {
        let ocrText = try await ocr(imageBase64: imagePNG.base64EncodedString())
        let hints = thinking ? [] : (try? await toolExtractionPass(ocrText: ocrText)) ?? []
        return try await chat(
            prompt: buildPrompt(ocrText: ocrText, renderFeedback: renderFeedback, toolHints: hints),
            imageBase64: imagePNG.base64EncodedString(),
            suppressTools: !hints.isEmpty
        )
    }

    /// Pass 1 for non-thinking mode: fires tools and returns computed results as hint strings.
    private func toolExtractionPass(ocrText: String) async throws -> [String] {
        let prompt = "Call the appropriate math tools for this expression, then stop. Do not write any text.\n\(ocrText)"
        let messages: [[String: Any]] = [["role": "user", "content": prompt]]
        var body = chatBody(messages: messages)
        body["think"] = false

        let data = try await send(body: body, timeout: 60)
        guard let outer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = outer["message"] as? [String: Any],
              let toolCalls = message["tool_calls"] as? [[String: Any]],
              !toolCalls.isEmpty else { return [] }

        // Execute tools and collect result strings
        return toolCalls.compactMap { toolCallDict -> String? in
            guard let d = try? JSONSerialization.data(withJSONObject: toolCallDict),
                  let toolCall = try? JSONDecoder().decode(ToolCall.self, from: d) else { return nil }
            let result = executeMathTool(toolCall)
            return "\(toolCall.function.name) = \(result)"
        }
    }

    private func buildPrompt(ocrText: String, renderFeedback: [String], toolHints: [String] = []) -> String {
        """
        The handwritten notes contain:
        \(ocrText)

        You autocomplete handwritten notes. Rules:
        1. Max 8 words or one short expression
        2. Only wrap math/symbols/numbers in [latex]...[/latex] tags
        3. NEVER use $ signs for math
        4. Output ONLY the suggestion, nothing else
        5. For any math problem, you MUST use the available tools: add, subtract, multiply, divide, abs, floor, gcd, solve_quadratic. Do not calculate math yourself.

        SUPPORTED LaTeX (use these):
        - Fractions: \\frac{a}{b}, \\dfrac, \\tfrac, \\cfrac
        - Scripts: x^2, x_i, x^{2}_{i}
        - Greek: \\alpha, \\beta, \\pi, \\sum, \\int
        - Matrices: \\begin{pmatrix}a & b \\\\ c & d\\end{pmatrix}
        - Matrix types: pmatrix (), bmatrix [], Bmatrix {}, vmatrix |, Vmatrix ||
        - Roots: \\sqrt{x}, \\sqrt[3]{x}
        - Delimiters: \\left( \\right), \\big, \\Big, \\bigg, \\Bigg
        - Dots: \\ldots, \\vdots, \\ddots, \\cdots

        UNSUPPORTED (NEVER use - will fail):
        - \\middle
        - Spacing: \\: \\; \\! \\hspace \\vspace
        - \\phantom, \\smash, \\rlap, \\llap
        - \\dots

        Examples:
        - "The area of a circle is" → [latex]A = \\pi r^2[/latex]
        - "Let x be a" → positive integer
        - "If f(x) = 3x + 1, then" → [latex]f(2) = 7[/latex]
        - "3+3" → [latex]= 6[/latex]
        - Matrix: [latex]\\begin{pmatrix} 1 & 2 \\\\ 3 & 4 \\end{pmatrix}[/latex]

        \(toolHints.isEmpty ? "" : "Computed arithmetic results: \(toolHints.joined(separator: ", "))\n")What comes next in these notes? If what is seen is a complete thought, suggest None.
        \(renderFeedback.isEmpty ? "" : """

        CRITICAL: Your previous LaTeX FAILED to render. Fix these issues:
        \(renderFeedback.joined(separator: "\n"))
        Use only SUPPORTED constructs listed above.
        """
        )
        """
    }

    private func ocr(imageBase64: String) async throws -> String {
        let body: [String: Any] = [
            "model": "glm-ocr:q8_0",
            "messages": [["role": "user", "content": "Text Recognition:", "images": [imageBase64]]],
            "stream": false,
            "options": ["temperature": 0]
        ]
        let data = try await send(body: body, timeout: 30)
        guard let outer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let msg = outer["message"] as? [String: Any],
              let text = msg["content"] as? String else { throw AgentError.invalidResponse }
        return text
    }

    private func chat(prompt: String, imageBase64: String?, suppressTools: Bool = false) async throws -> String {
        var userMsg: [String: Any] = ["role": "user", "content": prompt]
        if let img = imageBase64 { userMsg["images"] = [img] }
        var messages: [[String: Any]] = [userMsg]
        var body = chatBody(messages: messages, includeTools: !suppressTools)

        let data = try await send(body: body, timeout: 120)
        guard let outer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = outer["message"] as? [String: Any] else { throw AgentError.invalidResponse }

        let content = message["content"] as? String ?? ""

        let toolCalls = (message["tool_calls"] as? [[String: Any]])?.isEmpty == false
            ? message["tool_calls"] as! [[String: Any]]
            : parseFallbackToolCalls(from: content)

        if !toolCalls.isEmpty {
            messages = appendToolResults(toolCalls: toolCalls, assistantMessage: message, to: messages)
            body["messages"] = messages
            let finalData = try await send(body: body, timeout: 120)
            guard let fo = try? JSONSerialization.jsonObject(with: finalData) as? [String: Any],
                  let fm = fo["message"] as? [String: Any],
                  let text = fm["content"] as? String else { throw AgentError.invalidResponse }
            return text
        }

        guard !content.isEmpty else { throw AgentError.invalidResponse }
        return content
    }

    private func euclidGCD(_ a: Int, _ b: Int) -> Int { b == 0 ? abs(a) : euclidGCD(b, a % b) }

    private func solveQuadratic(a: Double, b: Double, c: Double) -> String {
        let discriminant = b * b - 4 * a * c
        toolCallLog.append("TOOL solve_quadratic(\(a), \(b), \(c)) discriminant=\(discriminant)")
        if discriminant < 0 {
            return "No real roots"
        } else if discriminant == 0 {
            let x = -b / (2 * a)
            return "x = \(format(x))"
        } else {
            let x1 = (-b + sqrt(discriminant)) / (2 * a)
            let x2 = (-b - sqrt(discriminant)) / (2 * a)
            return "x = \(format(x1)), x = \(format(x2))"
        }
    }

    private func format(_ d: Double) -> String {
        d.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(d)) : String(format: "%.4f", d)
    }

    /// Evaluates a fraction string like "5/6" → 0.8333
    private func parseFraction(_ s: String) -> Double? {
        let parts = s.split(separator: "/")
        guard parts.count == 2,
              let num = Double(parts[0]),
              let den = Double(parts[1]),
              den != 0 else { return nil }
        return num / den
    }

    /// Parses gemma4's non-JSON tool call format: `call:funcname{a=1,b=2}`
    private func parseFallbackToolCalls(from content: String) -> [[String: Any]] {
        let pattern = #"call:([\w.]+)\{([^}]*)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, range: range)

        return matches.compactMap { match -> [String: Any]? in
            guard let nameRange = Range(match.range(at: 1), in: content),
                  let argsRange = Range(match.range(at: 2), in: content) else { return nil }
            // Normalise name: Math.abs → abs, tool:foo → foo
            var rawName = String(content[nameRange])
            if rawName.hasPrefix("tool:") { rawName = String(rawName.dropFirst(5)) }
            let name = rawName.contains(".") ? String(rawName.split(separator: ".").last ?? Substring(rawName)) : rawName
            guard name != "none", !name.isEmpty else { return nil }
            let argString = String(content[argsRange])

            // Parse "a=1,b=2" or "a:1,b:2" or "a:5/6,b:5/3" or positional "-7" into args dict
            var argsDict: [String: Double] = [:]
            let pairs = argString.split(separator: ",")
            for pair in pairs {
                let parts = pair.split(whereSeparator: { $0 == "=" || $0 == ":" })
                if parts.count == 2 {
                    let key = String(parts[0].trimmingCharacters(in: .whitespaces))
                    let rawVal = String(parts[1].trimmingCharacters(in: .whitespaces))
                    if let val = Double(rawVal) { argsDict[key] = val }
                    else if let val = parseFraction(rawVal) { argsDict[key] = val }
                } else if parts.count == 1 {
                    // Positional single arg e.g. {-7}
                    let rawVal = String(pair.trimmingCharacters(in: .whitespaces))
                    let key = argsDict.isEmpty ? "a" : "b"
                    if let val = Double(rawVal) { argsDict[key] = val }
                    else if let val = parseFraction(rawVal) { argsDict[key] = val }
                }
            }
            guard let argsData = try? JSONEncoder().encode(argsDict),
                  let argsStr = String(data: argsData, encoding: .utf8) else { return nil }

            toolCallLog.append("FALLBACK parse: \(name)(\(argString))")

            return ["function": ["name": name, "arguments": argsStr]]
        }
    }

    private func appendToolResults(
        toolCalls: [[String: Any]],
        assistantMessage: [String: Any],
        to messages: [[String: Any]]
    ) -> [[String: Any]] {
        toolCalls.reduce(into: messages) { acc, toolCallDict in
            guard let d = try? JSONSerialization.data(withJSONObject: toolCallDict),
                  let toolCall = try? JSONDecoder().decode(ToolCall.self, from: d) else {
                toolCallLog.append("FAIL decode tool call")
                return
            }
            let result = executeMathTool(toolCall)
            acc.append(["role": "assistant", "content": assistantMessage["content"] as? String ?? "", "tool_calls": [toolCallDict]])
            acc.append(["role": "tool", "content": result, "tool_call_id": toolCall.id ?? ""])
        }
    }

    private func executeMathTool(_ toolCall: ToolCall) -> String {
        let name = toolCall.function.name
        guard name != "none", !name.isEmpty else { return "" }

        guard let data = toolCall.function.arguments.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            toolCallLog.append("FAIL invalid arguments for \(name)")
            return "Error: Invalid arguments"
        }

        // Detect symbolic args (e.g. multiply{a:x, b:n}) — skip silently
        let aVal = args["a"]; let bVal = args["b"]
        if aVal is String || bVal is String {
            toolCallLog.append("SKIP symbolic args for \(name)")
            return "Error: Symbolic arguments"
        }

        guard let a = (aVal as? Double) ?? (aVal as? Int).map(Double.init) else {
            toolCallLog.append("FAIL invalid arguments for \(name)")
            return "Error: Invalid arguments"
        }
        let b = (bVal as? Double) ?? (bVal as? Int).map(Double.init) ?? 0.0

        // solve_quadratic needs a third arg c
        if name == "solve_quadratic" {
            let c = (args["c"] as? Double) ?? (args["c"] as? Int).map(Double.init) ?? 0
            return solveQuadratic(a: a, b: b, c: c)
        }

        let result: Double
        switch name {
        case "add":      result = a + b
        case "subtract": result = a - b
        case "multiply": result = a * b
        case "abs":      result = abs(a)
        case "floor":    result = floor(a)
        case "gcd":      result = Double(euclidGCD(Int(a), Int(b)))
        case "min":      result = min(a, b)
        case "max":      result = max(a, b)
        case "divide":
            guard b != 0 else {
                toolCallLog.append("FAIL division by zero")
                return "Error: Division by zero"
            }
            result = a / b
        default:
            toolCallLog.append("FAIL unknown tool: \(name)")
            return "Error: Unknown tool"
        }
        toolCallLog.append("TOOL \(name)(\(a), \(b)) = \(result)")
        return String(format: "%.2f", result)
    }

    private func chatBody(messages: [[String: Any]], includeTools: Bool = true) -> [String: Any] {
        let toolsJSON = (try? JSONEncoder().encode(availableTools))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? []
        var body: [String: Any] = [
            "model": model, "messages": messages, "stream": false,
            "think": thinking, "options": ["temperature": 1.0, "top_p": 0.95, "top_k": 64]
        ]
        if includeTools { body["tools"] = toolsJSON }
        return body
    }

    private func send(body: [String: Any], timeout: TimeInterval) async throws -> Data {
        var req = URLRequest(url: URL(string: "http://\(host):\(port)/api/chat")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = timeout
        let (data, _) = try await URLSession.shared.data(for: req)
        return data
    }
}

// MARK: - Helpers

private func mathTool(_ name: String, _ description: String) -> Tool {
    Tool(type: "function", function: ToolFunction(
        name: name, description: description,
        parameters: ToolParameters(
            type: "object",
            properties: [
                "a": PropertyDefinition(type: "number", description: "First number"),
                "b": PropertyDefinition(type: "number", description: "Second number")
            ],
            required: ["a", "b"]
        )
    ))
}


public enum AgentError: LocalizedError {
    case invalidResponse
    case parseError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:     return "Invalid response from model"
        case .parseError(let raw): return "Parse error: \(raw.prefix(80))"
        }
    }
}
