import UIKit

@Observable
final class AgentOllamaClient {
    private let host = "100.121.248.31"
    private let port = 11434
    private let model = "qwen3.5:4b"

    /// Send birds-eye page image to Ollama. Returns a normalized tap point (0–1 in both axes).
    func selectTapPoint(image: UIImage) async throws -> CGPoint {
        guard let png = image.pngData(), !png.isEmpty else {
            throw AgentError.imageEncodingFailed
        }
        let base64 = png.base64EncodedString()

        let prompt = """
        You are looking at a handwritten notes page. \
        Identify a piece of content — a specific word, line, or equation that is clearly visible. No need to read what is is, just point to the location \
        Respond ONLY with a JSON object and nothing else: {"x":N,"y":N} \
        where x and y are normalized coordinates from 0.0 to 1.0 representing the center of that content \
        (0,0 = top-left corner, 1,1 = bottom-right corner). \
        Do not include explanation, markdown, or any other text. If nothing is found, repond with NONE
        """

        let body: [String: Any] = [
            "model": model,
            "messages": [[
                "role": "user",
                "content": prompt,
                "images": [base64]
            ]],
            "stream": false,
            "options": ["temperature": 0]
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

        print("[AgentOllama] raw response:\n\(responseText)\n---")
        let point = try parseTapPoint(from: responseText)
        print("[AgentOllama] parsed tap point: \(point)")
        return point
    }

    private func parseTapPoint(from text: String) throws -> CGPoint {
        // Strip <think>...</think> blocks (qwen3 thinking output)
        let stripped = text.replacingOccurrences(of: #"<think>[\s\S]*?</think>"#,
                                                  with: "", options: .regularExpression)
        let cleaned = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"\{[^{}]*"x"[^{}]*\}"#
        guard let range = cleaned.range(of: pattern, options: .regularExpression),
              let jsonData = String(cleaned[range]).data(using: .utf8),
              let dict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let x = (dict["x"] as? CGFloat) ?? (dict["x"] as? NSNumber).map(\.cgFloatValue),
              let y = (dict["y"] as? CGFloat) ?? (dict["y"] as? NSNumber).map(\.cgFloatValue)
        else {
            throw AgentError.parseError(cleaned)
        }
        return CGPoint(x: x.clamped(to: 0...1), y: y.clamped(to: 0...1))
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

private extension NSNumber {
    var cgFloatValue: CGFloat { CGFloat(doubleValue) }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
