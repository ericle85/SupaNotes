import UIKit

@Observable
final class AgentOllamaClient {
    private let host = "100.121.248.31"
    private let port = 11434
    private let model = "qwen3.5:4b"

    enum ContentType: String {
        case text
        case math
    }

    /// Classify a cropped region as regular text or math/equations.
    func classifyContent(image: UIImage) async throws -> ContentType {
        guard let png = image.pngData(), !png.isEmpty else {
            throw AgentError.imageEncodingFailed
        }
        let base64 = png.base64EncodedString()

        let prompt = """
        Look at this cropped handwritten content. \
        Is it regular text, or does it contain math/equations? \
        Respond with ONLY one word: "text" or "math".
        """

        let response = try await chat(prompt: prompt, imageBase64: base64)
        let cleaned = response.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        print("[AgentOllama] classify response: \(cleaned)")

        if cleaned.contains("math") { return .math }
        return .text
    }

    /// Send page image + stroke bounding boxes to Ollama.
    /// Returns a CGRect in image space (612×792) around selected content.
    /// NOT BEING USED CURRENTLY - SEE `classifyContent` INSTEAD
    /// HAVE MADE BOUNDING BOX SLECTION BE MANUAL
    func selectRegion(image: UIImage, strokesJSON: String) async throws -> CGRect {
        guard let png = image.pngData(), !png.isEmpty else {
            throw AgentError.imageEncodingFailed
        }
        let base64 = png.base64EncodedString()

        let prompt = """
        You are looking at a handwritten notes page. \
        Here are the bounding boxes of all strokes on the page: \
        \(strokesJSON)
        Each stroke has: id, x1, y1 (top-left), x2, y2 (bottom-right). \
        Pick a meaningful piece of content (a word, line, or equation). \
        Your rectangle MUST use the min x1,y1 and max x2,y2 of the strokes you select. \
        Respond ONLY with: {"x1":N,"y1":N,"x2":N,"y2":N} \
        If nothing is found: {}
        """

        let responseText = try await chat(prompt: prompt, imageBase64: base64)
        print("[AgentOllama] raw response:\n\(responseText)\n---")
        let rect = try parseRect(from: responseText)
        print("[AgentOllama] parsed rect: \(rect)")
        return rect
    }

    /// Suggest what comes next in the user's handwritten notes.
    func suggest(image: UIImage) async throws -> String {
        guard let png = image.pngData(), !png.isEmpty else {
            throw AgentError.imageEncodingFailed
        }
        let base64 = png.base64EncodedString()

        let prompt = """
        You autocomplete handwritten notes. Rules:
        1. Max 8 words or one short expression
        2. Wrap ALL math/symbols/numbers in [latex]...[/latex] tags
        3. NEVER use $ signs for math
        4. Output ONLY the suggestion, nothing else

        Examples:
        - "The area of a circle is" → [latex]A = \\pi r^2[/latex]
        - "Let x be a" → positive integer
        - "If f(x) = 3x + 1, then" → [latex]f(2) = 7[/latex]
        - "The Schrödinger equation describes" → the time evolution of [latex]\\psi[/latex]

        What comes next in these notes?
        """

        return try await chat(prompt: prompt, imageBase64: base64)
    }

    // MARK: - Shared request

    private func chat(prompt: String, imageBase64: String) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "messages": [[
                "role": "user",
                "content": prompt,
                "images": [imageBase64]
            ]],
            "stream": false,
            "think": false,
            "options": ["temperature": 0, "top_p": 0.9, "top_k": 20]
        ]

        var request = URLRequest(url: URL(string: "http://\(host):\(port)/api/chat")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let outer = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = outer["message"] as? [String: Any],
              let responseText = message["content"] as? String else {
            let raw = String(data: data, encoding: .utf8) ?? "nil"
            print("[AgentOllama] unexpected response: \(raw.prefix(300))")
            throw AgentError.invalidResponse
        }
        return responseText
    }

    // MARK: - Parsing

    private func parseRect(from text: String) throws -> CGRect {
        let stripped = text.replacingOccurrences(of: #"<think>[\s\S]*?</think>"#,
                                                  with: "", options: .regularExpression)
        let cleaned = stripped.trimmingCharacters(in: .whitespacesAndNewlines)

        let pattern = #"\{[^{}]*"x1"[^{}]*\}"#
        guard let range = cleaned.range(of: pattern, options: .regularExpression),
              let jsonData = String(cleaned[range]).data(using: .utf8),
              let dict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            if cleaned.contains("{}") { throw AgentError.parseError("empty") }
            throw AgentError.parseError(cleaned)
        }

        func num(_ key: String) -> CGFloat? {
            (dict[key] as? CGFloat) ?? (dict[key] as? NSNumber).map { CGFloat($0.doubleValue) }
        }

        guard let x1 = num("x1"), let y1 = num("y1"),
              let x2 = num("x2"), let y2 = num("y2") else {
            throw AgentError.parseError(cleaned)
        }

        return CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1)
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

