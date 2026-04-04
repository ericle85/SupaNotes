import Foundation

struct OverlayTokenizer {
    /// Parse LLM response into tokens. Text outside [latex] tags becomes word tokens,
    /// text inside becomes latex tokens.
    func tokenize(_ raw: String) -> [OverlayToken] {
        let normalized = normalize(raw)
        var tokens: [OverlayToken] = []

        let pattern = #"\[latex\](.*?)\[/latex\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else {
            return wordTokens(from: normalized)
        }

        let nsString = normalized as NSString
        var lastEnd = 0

        let matches = regex.matches(in: normalized, range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            // Text before this latex block → word tokens
            let beforeRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
            if beforeRange.length > 0 {
                let text = nsString.substring(with: beforeRange)
                tokens.append(contentsOf: wordTokens(from: text))
            }

            // Latex content
            let latexContent = nsString.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !latexContent.isEmpty {
                tokens.append(OverlayToken(
                    type: .latex,
                    value: latexContent,
                    displayLatex: latexContent
                ))
            }

            lastEnd = match.range.location + match.range.length
        }

        // Trailing text
        if lastEnd < nsString.length {
            let trailing = nsString.substring(from: lastEnd)
            // Bare latex fallback: if it has backslashes or braces, treat as latex
            if looksLikeBareLatex(trailing) {
                tokens.append(OverlayToken(
                    type: .latex,
                    value: trailing.trimmingCharacters(in: .whitespacesAndNewlines),
                    displayLatex: trailing.trimmingCharacters(in: .whitespacesAndNewlines)
                ))
            } else {
                tokens.append(contentsOf: wordTokens(from: trailing))
            }
        }

        return tokens
    }

    // MARK: - Private

    private func normalize(_ raw: String) -> String {
        var s = raw
        // Strip $ wrappers
        s = s.replacingOccurrences(of: "$", with: "")
        // Fix [latex]...[latex] → [latex]...[/latex]
        let broken = #"\[latex\](.*?)\[latex\]"#
        if let re = try? NSRegularExpression(pattern: broken, options: .dotMatchesLineSeparators) {
            s = re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length),
                                            withTemplate: "[latex]$1[/latex]")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func wordTokens(from text: String) -> [OverlayToken] {
        text.split(separator: " ", omittingEmptySubsequences: true).map { word in
            let w = String(word).trimmingCharacters(in: .whitespacesAndNewlines)
            return OverlayToken(type: .word, value: w, displayLatex: "\\text{\(w)}")
        }
    }

    private func looksLikeBareLatex(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("\\") || trimmed.contains("{") || trimmed.contains("^") || trimmed.contains("_")
    }
}
