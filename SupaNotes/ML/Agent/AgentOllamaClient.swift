import UIKit

// MARK: - Types

struct Tool: Codable {
    let type: String
    let function: ToolFunction
}

struct ToolFunction: Codable {
    let name: String
    let description: String
    let parameters: ToolParameters
}

struct ToolParameters: Codable {
    let type: String
    let properties: [String: PropertyDefinition]
    let required: [String]
}

struct PropertyDefinition: Codable {
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

@Observable
final class AgentOllamaClient {
    private let host = "100.121.248.31"
    private let port = 11434
    private let model = "gemma4:e4b-it-q4_K_M"

    private let availableTools: [Tool] = [
        mathTool("add", "Add two numbers together. Use this for any addition or subtraction operations."),
        mathTool("multiply", "Multiply two numbers together. Use this for any multiplication operations."),
        mathTool("divide", "Divide a by b. Use this for any division operations.")
    ]

    func suggest(image: UIImage, renderFeedback: [String] = []) async throws -> String {
        guard let png = image.pngData(), !png.isEmpty else { throw AgentError.imageEncodingFailed }
        let ocrText = try await ocr(imageBase64: png.base64EncodedString())

        let smallImage = image.resized(toMaxDimension: 512)
        guard let smallPng = smallImage.pngData(), !smallPng.isEmpty else { throw AgentError.imageEncodingFailed }

        let prompt = """
        The handwritten notes contain:
        \(ocrText)

        You autocomplete handwritten notes. Rules:
        1. Max 8 words or one short expression
        2. Only wrap math/symbols/numbers in [latex]...[/latex] tags
        3. NEVER use $ signs for math
        4. Output ONLY the suggestion, nothing else
        5. For any math problem, you MUST use the available tools: add(a, b), multiply(a, b), divide(a, b). Do not calculate math yourself.

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

        What comes next in these notes? If what is seen is a complete thought, suggest None.
        \(renderFeedback.isEmpty ? "" : """

        CRITICAL: Your previous LaTeX FAILED to render. Fix these issues:
        \(renderFeedback.joined(separator: "\n"))
        Use only SUPPORTED constructs listed above.
        """
        )
        """

        return try await chat(prompt: prompt, imageBase64: smallPng.base64EncodedString())
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
        print("[AgentOllama] GLM OCR result: \(text)")
        return text
    }

    private func chat(prompt: String, imageBase64: String) async throws -> String {
        var messages: [[String: Any]] = [["role": "user", "content": prompt, "images": [imageBase64]]]
        var body = chatBody(messages: messages)

        let data = try await send(body: body, timeout: 120)
        guard let outer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = outer["message"] as? [String: Any] else { throw AgentError.invalidResponse }

        if let toolCalls = message["tool_calls"] as? [[String: Any]], !toolCalls.isEmpty {
            print("[AgentOllama] 🔍 Model requested tool calls: \(toolCalls.count)")
            messages = appendToolResults(toolCalls: toolCalls, assistantMessage: message, to: messages)
            body["messages"] = messages
            let finalData = try await send(body: body, timeout: 120)
            guard let fo = try? JSONSerialization.jsonObject(with: finalData) as? [String: Any],
                  let fm = fo["message"] as? [String: Any],
                  let text = fm["content"] as? String else { throw AgentError.invalidResponse }
            return text
        }

        guard let text = message["content"] as? String else { throw AgentError.invalidResponse }
        return text
    }

    private func appendToolResults(
        toolCalls: [[String: Any]],
        assistantMessage: [String: Any],
        to messages: [[String: Any]]
    ) -> [[String: Any]] {
        toolCalls.reduce(into: messages) { acc, toolCallDict in
            guard let d = try? JSONSerialization.data(withJSONObject: toolCallDict),
                  let toolCall = try? JSONDecoder().decode(ToolCall.self, from: d) else {
                print("[AgentOllama] ❌ Failed to decode tool call")
                return
            }
            let result = executeMathTool(toolCall)
            acc.append(["role": "assistant", "content": assistantMessage["content"] as? String ?? "", "tool_calls": [toolCallDict]])
            acc.append(["role": "tool", "content": result, "tool_call_id": toolCall.id ?? ""])
        }
    }

    private func chatBody(messages: [[String: Any]]) -> [String: Any] {
        let toolsJSON = (try? JSONEncoder().encode(availableTools))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? []
        return [
            "model": model, "messages": messages, "stream": false,
            "think": true, "tools": toolsJSON,
            "options": ["temperature": 1.0, "top_p": 0.95, "top_k": 64]
        ]
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

private func executeMathTool(_ toolCall: ToolCall) -> String {
    guard let data = toolCall.function.arguments.data(using: .utf8),
          let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let a = (args["a"] as? Double) ?? (args["a"] as? Int).map(Double.init),
          let b = (args["b"] as? Double) ?? (args["b"] as? Int).map(Double.init) else {
        print("[AgentOllama] ❌ Invalid arguments for \(toolCall.function.name)")
        return "Error: Invalid arguments"
    }
    let result: Double
    switch toolCall.function.name {
    case "add":      result = a + b
    case "multiply": result = a * b
    case "divide":
        guard b != 0 else { return "Error: Division by zero" }
        result = a / b
    default:
        print("[AgentOllama] ❌ Unknown tool: \(toolCall.function.name)")
        return "Error: Unknown tool"
    }
    print("[AgentOllama] 🔧 \(toolCall.function.name)(\(a), \(b)) = \(result)")
    return String(format: "%.2f", result)
}

private extension UIImage {
    func resized(toMaxDimension maxDim: CGFloat) -> UIImage {
        let scale = min(maxDim / size.width, maxDim / size.height, 1)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: newSize).image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}

enum AgentError: LocalizedError {
    case imageEncodingFailed
    case invalidResponse
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .imageEncodingFailed: return "Failed to encode image"
        case .invalidResponse:     return "Invalid response from model"
        case .parseError(let raw): return "Parse error: \(raw.prefix(80))"
        }
    }
}
