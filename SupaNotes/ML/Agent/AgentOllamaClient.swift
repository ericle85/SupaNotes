import UIKit

@Observable
final class AgentOllamaClient {
    private let host = "100.121.248.31"
    private let port = 11434
    private let model = "gemma4:26b"

    /// Suggest what comes next in the user's handwritten notes.
    func suggest(image: UIImage) async throws -> String {
        guard let png = image.pngData(), !png.isEmpty else {
            throw AgentError.imageEncodingFailed
        }
        let base64 = png.base64EncodedString()

        let prompt = """
        You autocomplete handwritten notes. Rules:
        1. Max 8 words or one short expression
        2. Only wrap math/symbols/numbers in [latex]...[/latex] tags
        3. NEVER use $ signs for math
        4. Output ONLY the suggestion, nothing else

        Examples:
        - "The area of a circle is" → [latex]A = \\pi r^2[/latex]
        - "Let x be a" → positive integer
        - "If f(x) = 3x + 1, then" → [latex]f(2) = 7[/latex]
        - "The Schrödinger equation describes" → the time evolution of [latex]\\psi[/latex] (keep in mind that regular text is not wrapped in latex tags, only math/symbols/numbers)

        - "3+3" → [latex]= 6[/latex]
        - "3+3=" → [latex]6[/latex]


        When given matrix arithmetic, answers should be in the form of a matrix in latex.

        What comes next in these notes? If what is seen is a complete thought, suggest None.
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
            "think": true,
            "options": ["temperature": 1.0, "top_p": 0.95, "top_k": 64]
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
