import UIKit

@Observable
final class AgentOllamaClient {
    private let host = "100.121.248.31"
    private let port = 11434
    private let model = "gemma4:e4b-it-q4_K_M"

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
        print("[AgentOllama] GLM OCR result: \(text)")
        return text
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
