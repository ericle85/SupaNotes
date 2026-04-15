import UIKit

// MARK: - Tool Definitions

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
    let arguments: String  // normalized to JSON string

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        // Ollama sends arguments as a dict; normalize to JSON string
        if let str = try? c.decode(String.self, forKey: .arguments) {
            arguments = str
        } else {
            let dict = try c.decode([String: AnyCodable].self, forKey: .arguments)
            let data = try JSONEncoder().encode(dict)
            arguments = String(data: data, encoding: .utf8) ?? "{}"
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

    init(_ value: Any) { self.value = value }

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

// MARK: - Math Tool Functions

@Observable
final class AgentOllamaClient {
    private let host = "100.121.248.31"
    private let port = 11434
    private let model = "gemma4:e4b-it-q4_K_M"

    private let availableTools: [Tool] = [
        Tool(
            type: "function",
            function: ToolFunction(
                name: "add",
                description: "Add two numbers together. Use this for any addition operations.",
                parameters: ToolParameters(
                    type: "object",
                    properties: [
                        "a": PropertyDefinition(type: "number", description: "First number to add"),
                        "b": PropertyDefinition(type: "number", description: "Second number to add")
                    ],
                    required: ["a", "b"]
                )
            )
        ),
        Tool(
            type: "function",
            function: ToolFunction(
                name: "multiply",
                description: "Multiply two numbers together. Use this for any multiplication operations.",
                parameters: ToolParameters(
                    type: "object",
                    properties: [
                        "a": PropertyDefinition(type: "number", description: "First number to multiply"),
                        "b": PropertyDefinition(type: "number", description: "Second number to multiply")
                    ],
                    required: ["a", "b"]
                )
            )
        )
    ]

    private func executeToolCall(_ toolCall: ToolCall) -> String {
        guard let argumentsData = toolCall.function.arguments.data(using: .utf8),
              let arguments = try? JSONSerialization.jsonObject(with: argumentsData) as? [String: Any],
              let a = arguments["a"] as? Double,
              let b = arguments["b"] as? Double else {
            print("[AgentOllama] ❌ Tool call failed: invalid arguments for \(toolCall.function.name)")
            return "Error: Invalid arguments"
        }

        let result: Double
        switch toolCall.function.name {
        case "add":
            result = a + b
            print("[AgentOllama] 🔧 Tool called: add(\(a), \(b)) = \(result)")
        case "multiply":
            result = a * b
            print("[AgentOllama] 🔧 Tool called: multiply(\(a), \(b)) = \(result)")
        default:
            print("[AgentOllama] ❌ Unknown tool: \(toolCall.function.name)")
            return "Error: Unknown tool"
        }

        return String(format: "%.2f", result)
    }

    /// Suggest what comes next in the user's handwritten notes.
    func suggest(image: UIImage, renderFeedback: [String] = []) async throws -> String {
        guard let png = image.pngData(), !png.isEmpty else {
            throw AgentError.imageEncodingFailed
        }

        // Step 1: GLM-OCR reads the image
        let ocrText = try await ocr(imageBase64: png.base64EncodedString())

        // Step 2: Gemma reasons on OCR output + lower-res image
        let smallImage = image.resized(toMaxDimension: 512)
        guard let smallPng = smallImage.pngData(), !smallPng.isEmpty else {
            throw AgentError.imageEncodingFailed
        }

        let prompt = """
        The handwritten notes contain:
        \(ocrText)

        You autocomplete handwritten notes. Rules:
        1. Max 8 words or one short expression
        2. Only wrap math/symbols/numbers in [latex]...[/latex] tags
        3. NEVER use $ signs for math
        4. Output ONLY the suggestion, nothing else
        5. For any math problem (addition, multiplication), you MUST use the available tools: add(a, b) and multiply(a, b). Do not calculate math yourself.

        SUPPORTED LaTeX (use these):
        - Fractions: \\frac{a}{b}, \\dfrac, \\tfrac, \\cfrac
        - Scripts: x^2, x_i, x^{2}_{i}
        - Greek: \\alpha, \\beta, \\pi, \\sum, \\int
        - Matrices: \\begin{pmatrix}a & b \\\\ c & d\\end{pmatrix}
        - Matrix types: pmatrix (), bmatrix [], Bmatrix {}, vmatrix |, Vmatrix ||
        - Roots: \\sqrt{x}, \\sqrt[3]{x}
        - Delimiters: \\left( \\right), \\big, \\Big, \\bigg, \\Bigg

        UNSUPPORTED (NEVER use - will fail):
        - \\middle
        - Spacing: \\: \\; \\! \\hspace \\vspace
        - \\phantom, \\smash, \\rlap, \\llap

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


    // MARK: - OCR
    private func ocr(imageBase64: String) async throws -> String {
        let body: [String: Any] = [
            "model": "glm-ocr:q8_0",
            "messages": [[
                "role": "user",
                "content": "Text Recognition:",
                "images": [imageBase64]
            ]],
            "stream": false,
            "options": ["temperature": 0]
        ]

        var request = URLRequest(url: URL(string: "http://\(host):\(port)/api/chat")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let outer = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = outer["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw AgentError.invalidResponse
        }
        // MARK: - Debug: OCR result
        print("[AgentOllama] GLM OCR result: \(text)")
        return text
    }

    // MARK: - Shared request

    private func chat(prompt: String, imageBase64: String) async throws -> String {
        var messages: [[String: Any]] = [[
            "role": "user",
            "content": prompt,
            "images": [imageBase64]
        ]]

        var body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": false,
            "think": true,
            "options": ["temperature": 1.0, "top_p": 0.95, "top_k": 64]
        ]

        // Add tools to the request
        let toolsData = try JSONEncoder().encode(availableTools)
        if let toolsJSON = try? JSONSerialization.jsonObject(with: toolsData) as? [[String: Any]] {
            body["tools"] = toolsJSON
        }

        var request = URLRequest(url: URL(string: "http://\(host):\(port)/api/chat")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let outer = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = outer["message"] as? [String: Any] else {
            let raw = String(data: data, encoding: .utf8) ?? "nil"
            // MARK: - Debug: Unexpected response
            // print("[AgentOllama] unexpected response: \(raw.prefix(300))")
            throw AgentError.invalidResponse
        }

        // Check if the model wants to call a tool
        if let toolCalls = message["tool_calls"] as? [[String: Any]],
           !toolCalls.isEmpty {
            print("[AgentOllama] 🔍 Model requested tool calls: \(toolCalls.count)")

            // Execute each tool call and build response messages
            for toolCallDict in toolCalls {
                guard let toolCallData = try? JSONSerialization.data(withJSONObject: toolCallDict),
                      let toolCall = try? JSONDecoder().decode(ToolCall.self, from: toolCallData) else {
                    print("[AgentOllama] ❌ Failed to decode tool call")
                    continue
                }

                let toolResult = executeToolCall(toolCall)

                // Add assistant message with tool call
                messages.append([
                    "role": "assistant",
                    "content": message["content"] as? String ?? "",
                    "tool_calls": [toolCallDict]
                ])

                // Add tool response message
                messages.append([
                    "role": "tool",
                    "content": toolResult,
                    "tool_call_id": toolCall.id ?? ""
                ])
            }

            // Send the messages back to get the final response
            body["messages"] = messages
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (finalData, _) = try await URLSession.shared.data(for: request)

            guard let finalOuter = try JSONSerialization.jsonObject(with: finalData) as? [String: Any],
                  let finalMessage = finalOuter["message"] as? [String: Any],
                  let responseText = finalMessage["content"] as? String else {
                let raw = String(data: finalData, encoding: .utf8) ?? "nil"
                print("[AgentOllama] ❌ Failed to get final response after tool call: \(raw.prefix(300))")
                throw AgentError.invalidResponse
            }

            print("[AgentOllama] ✅ Final response after tool execution")
            return responseText
        }

        // No tool calls, return the response directly
        guard let responseText = message["content"] as? String else {
            throw AgentError.invalidResponse
        }

        return responseText
    }
}

private extension UIImage {
    func resized(toMaxDimension maxDim: CGFloat) -> UIImage {
        let scale = min(maxDim / size.width, maxDim / size.height, 1)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: newSize).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

enum AgentError: LocalizedError {
    case imageEncodingFailed
    case invalidResponse
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .imageEncodingFailed: return "Failed to encode image"
        case .invalidResponse: return "Invalid response from model"
        case .parseError(let raw): return "Parse error: \(raw.prefix(80))"
        }
    }
}
