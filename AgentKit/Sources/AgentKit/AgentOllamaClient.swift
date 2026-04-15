import Foundation

// MARK: - Client

public final class AgentOllamaClient {
    private let host: String
    private let port: Int
    private let model: String
    private let thinking: Bool

    private static let promptTemplate: String = {
        guard let url = Bundle.module.url(forResource: "SuggestionPrompt", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8),
              !text.isEmpty else {
            fatalError("SuggestionPrompt.md missing or empty from bundle")
        }
        return text
    }()

    public private(set) var toolCallLog: [String] = []
    public func clearLog() { toolCallLog = [] }

    public init(host: String = "100.121.248.31", port: Int = 11434, model: String = "gemma4:e4b-it-q4_K_M", thinking: Bool = true) {
        self.host = host
        self.port = port
        self.model = model
        self.thinking = thinking
    }

    // MARK: - Public API

    public func suggest(text ocrText: String, renderFeedback: [String] = []) async throws -> String {
        let hints = thinking ? [] : (try? await toolExtractionPass(ocrText: ocrText)) ?? []
        return try await chat(
            prompt: buildPrompt(ocrText: ocrText, renderFeedback: renderFeedback, toolHints: hints),
            imageBase64: nil,
            suppressTools: !hints.isEmpty
        )
    }

    public func suggest(imagePNG: Data, renderFeedback: [String] = []) async throws -> String {
        let ocrText = try await ocr(imageBase64: imagePNG.base64EncodedString())
        let hints = thinking ? [] : (try? await toolExtractionPass(ocrText: ocrText)) ?? []
        return try await chat(
            prompt: buildPrompt(ocrText: ocrText, renderFeedback: renderFeedback, toolHints: hints),
            imageBase64: imagePNG.base64EncodedString(),
            suppressTools: !hints.isEmpty
        )
    }

    // MARK: - Prompt

    private func buildPrompt(ocrText: String, renderFeedback: [String], toolHints: [String] = []) -> String {
        let hints = toolHints.isEmpty ? "" : "Computed arithmetic results: \(toolHints.joined(separator: ", "))\n"
        let feedback = renderFeedback.isEmpty ? "" : """

        CRITICAL: Your previous LaTeX FAILED to render. Fix these issues:
        \(renderFeedback.joined(separator: "\n"))
        Use only SUPPORTED constructs listed above.
        """
        return """
        The handwritten notes contain:
        \(ocrText)

        \(Self.promptTemplate)
        \(hints)What comes next in these notes? If what is seen is a complete thought, suggest None.\(feedback)
        """
    }

    // MARK: - Tool Extraction Pass

    private func toolExtractionPass(ocrText: String) async throws -> [String] {
        let prompt = "Call the appropriate math tools for this expression, then stop. Do not write any text.\n\(ocrText)"
        let messages: [[String: Any]] = [["role": "user", "content": prompt]]
        var body = chatBody(messages: messages, includeTools: true)
        body["think"] = false

        let data = try await send(body: body, timeout: 60)
        guard let outer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = outer["message"] as? [String: Any],
              let toolCalls = message["tool_calls"] as? [[String: Any]],
              !toolCalls.isEmpty else { return [] }

        return toolCalls.compactMap { dict -> String? in
            guard let d = try? JSONSerialization.data(withJSONObject: dict),
                  let toolCall = try? JSONDecoder().decode(ToolCall.self, from: d) else { return nil }
            let result = executeMathTool(toolCall, log: &toolCallLog)
            return "\(toolCall.function.name) = \(result)"
        }
    }

    // MARK: - Chat

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

    private func appendToolResults(
        toolCalls: [[String: Any]],
        assistantMessage: [String: Any],
        to messages: [[String: Any]]
    ) -> [[String: Any]] {
        toolCalls.reduce(into: messages) { acc, dict in
            guard let d = try? JSONSerialization.data(withJSONObject: dict),
                  let toolCall = try? JSONDecoder().decode(ToolCall.self, from: d) else {
                toolCallLog.append("FAIL decode tool call")
                return
            }
            let result = executeMathTool(toolCall, log: &toolCallLog)
            acc.append(["role": "assistant", "content": assistantMessage["content"] as? String ?? "", "tool_calls": [dict]])
            acc.append(["role": "tool", "content": result, "tool_call_id": toolCall.id ?? ""])
        }
    }

    // MARK: - Request Helpers

    private func chatBody(messages: [[String: Any]], includeTools: Bool = true) -> [String: Any] {
        let toolsJSON = (try? JSONEncoder().encode(mathTools))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? []
        var body: [String: Any] = [
            "model": model, "messages": messages, "stream": false,
            "think": thinking, "options": ["temperature": 1.0, "top_p": 0.95, "top_k": 64]
        ]
        if includeTools { body["tools"] = toolsJSON }
        return body
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

// MARK: - Errors

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
