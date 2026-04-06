import Foundation

/// Recursive tree representing a parsed LaTeX expression.
indirect enum MathNode {
    case glyph(String)
    case fraction(numerator: [MathNode], denominator: [MathNode])
    case script(base: MathNode, sub: [MathNode]?, sup: [MathNode]?)
    case delimited(open: String, close: String, content: [MathNode])
    case matrix(rows: [[[MathNode]]], open: String, close: String)
    case row([MathNode])
    case sqrt(content: [MathNode])
    case accent(symbol: String, content: [MathNode]) // \vec, \hat, \bar, \dot, \tilde, \overline
    case space
    case text(String)
    case fracLine
}

// MARK: - Symbol Map

let latexSymbolMap: [String: String] = [
    "\\sum": "∑", "\\prod": "∏", "\\int": "∫", "\\oint": "∮",
    "\\pi": "π", "\\alpha": "α", "\\beta": "β", "\\gamma": "γ",
    "\\delta": "δ", "\\epsilon": "ε", "\\zeta": "ζ", "\\eta": "η",
    "\\theta": "θ", "\\iota": "ι", "\\kappa": "κ", "\\lambda": "λ",
    "\\mu": "μ", "\\nu": "ν", "\\xi": "ξ", "\\rho": "ρ",
    "\\sigma": "σ", "\\tau": "τ", "\\upsilon": "υ", "\\phi": "φ",
    "\\chi": "χ", "\\psi": "ψ", "\\omega": "ω",
    "\\Gamma": "Γ", "\\Delta": "Δ", "\\Theta": "Θ", "\\Lambda": "Λ",
    "\\Xi": "Ξ", "\\Pi": "Π", "\\Sigma": "Σ", "\\Phi": "Φ",
    "\\Psi": "Ψ", "\\Omega": "Ω",
    "\\infty": "∞", "\\partial": "∂", "\\nabla": "∇",
    "\\times": "×", "\\div": "÷", "\\cdot": "·", "\\pm": "±", "\\mp": "∓",
    "\\le": "≤", "\\leq": "≤", "\\ge": "≥", "\\geq": "≥",
    "\\ne": "≠", "\\neq": "≠", "\\approx": "≈", "\\equiv": "≡",
    "\\subset": "⊂", "\\supset": "⊃", "\\subseteq": "⊆", "\\supseteq": "⊇",
    "\\in": "∈", "\\notin": "∉", "\\cup": "∪", "\\cap": "∩",
    "\\rightarrow": "→", "\\leftarrow": "←", "\\Rightarrow": "⇒",
    "\\Leftarrow": "⇐", "\\leftrightarrow": "↔",
    "\\forall": "∀", "\\exists": "∃",
    "\\sqrt": "√", "\\neg": "¬", "\\wedge": "∧", "\\vee": "∨",
    "\\to": "→", "\\mapsto": "↦",
    "\\lim": "lim", "\\max": "max", "\\min": "min",
    "\\sin": "sin", "\\cos": "cos", "\\tan": "tan",
    "\\log": "log", "\\ln": "ln", "\\exp": "exp",
    "\\det": "det", "\\dim": "dim", "\\ker": "ker",
]

let mathbbMap: [Character: String] = [
    "A": "𝔸", "B": "𝔹", "C": "ℂ", "D": "𝔻", "E": "𝔼", "F": "𝔽", "G": "𝔾",
    "H": "ℍ", "I": "𝕀", "J": "𝕁", "K": "𝕂", "L": "𝕃", "M": "𝕄", "N": "ℕ",
    "O": "𝕆", "P": "ℙ", "Q": "ℚ", "R": "ℝ", "S": "𝕊", "T": "𝕋", "U": "𝕌",
    "V": "𝕍", "W": "𝕎", "X": "𝕏", "Y": "𝕐", "Z": "ℤ",
]

// MARK: - Parser

struct MathParser {
    func parse(_ latex: String) -> [MathNode] {
        var i = latex.startIndex
        return parseNodes(latex, from: &i, until: nil)
    }

    private func parseNodes(_ s: String, from i: inout String.Index, until terminator: Character?) -> [MathNode] {
        var nodes: [MathNode] = []
        while i < s.endIndex {
            let ch = s[i]
            if let t = terminator, ch == t { i = s.index(after: i); break }

            if ch == "\\" {
                let cmd = readCommand(s, from: &i)
                if let node = handleCommand(cmd, s, from: &i) {
                    nodes.append(node)
                }
            } else if ch == "^" || ch == "_" {
                // Attach script to previous node
                let base = nodes.isEmpty ? .glyph("") : nodes.removeLast()
                let scriptNode = readScript(base, s, from: &i)
                nodes.append(scriptNode)
            } else if ch == "{" {
                i = s.index(after: i)
                let inner = parseNodes(s, from: &i, until: "}")
                nodes.append(contentsOf: inner)
            } else if ch == "}" {
                i = s.index(after: i)
                break
            } else if ch == " " {
                i = s.index(after: i)
            } else if ch == "&" || ch == "\n" {
                i = s.index(after: i)
            } else {
                nodes.append(.glyph(String(ch)))
                i = s.index(after: i)
            }
        }
        return nodes
    }

    private func readCommand(_ s: String, from i: inout String.Index) -> String {
        var cmd = "\\"
        i = s.index(after: i) // skip backslash
        guard i < s.endIndex else { return cmd }

        if !s[i].isLetter {
            cmd.append(s[i])
            i = s.index(after: i)
            return cmd
        }
        while i < s.endIndex && s[i].isLetter {
            cmd.append(s[i])
            i = s.index(after: i)
        }
        return cmd
    }

    private func handleCommand(_ cmd: String, _ s: String, from i: inout String.Index) -> MathNode? {
        switch cmd {
        case "\\frac", "\\dfrac", "\\tfrac":
            let num = readBraceGroup(s, from: &i)
            let den = readBraceGroup(s, from: &i)
            return .fraction(numerator: num, denominator: den)

        case "\\begin":
            return handleEnvironment(s, from: &i)

        case "\\left":
            return handleDelimited(s, from: &i)

        case "\\text", "\\mathrm", "\\mathbf", "\\operatorname":
            let content = readBraceGroupRaw(s, from: &i)
            return .text(content)

        case "\\mathbb":
            let content = readBraceGroupRaw(s, from: &i)
            let mapped = content.map { ch -> String in
                if let bb = mathbbMap[ch] { return bb }
                return String(ch)
            }.joined()
            return .text(mapped)

        case "\\;", "\\,", "\\!", "\\ ", "\\quad", "\\qquad":
            return .space

        case "\\\\":
            return nil // row separator, handled by matrix/environment

        case "\\sqrt":
            let content = readBraceGroup(s, from: &i)
            return .sqrt(content: content)

        case "\\vec":
            let content = readBraceGroup(s, from: &i)
            return .accent(symbol: "→", content: content)
        case "\\hat":
            let content = readBraceGroup(s, from: &i)
            return .accent(symbol: "^", content: content)
        case "\\bar", "\\overline":
            let content = readBraceGroup(s, from: &i)
            return .accent(symbol: "—", content: content)
        case "\\dot":
            let content = readBraceGroup(s, from: &i)
            return .accent(symbol: "·", content: content)
        case "\\ddot":
            let content = readBraceGroup(s, from: &i)
            return .accent(symbol: "··", content: content)
        case "\\tilde":
            let content = readBraceGroup(s, from: &i)
            return .accent(symbol: "~", content: content)
        case "\\underline":
            let content = readBraceGroup(s, from: &i)
            return .accent(symbol: "_", content: content)

        default:
            if let symbol = latexSymbolMap[cmd] {
                let node = MathNode.glyph(symbol)
                // Check for trailing scripts
                return maybeScript(node, s, from: &i)
            }
            // Unknown command — render as text
            let name = String(cmd.dropFirst()) // strip backslash
            return .text(name)
        }
    }

    private func handleEnvironment(_ s: String, from i: inout String.Index) -> MathNode? {
        let envName = readBraceGroupRaw(s, from: &i)
        let endMarker = "\\end{\(envName)}"

        // Collect inner content until \end{envName}
        var inner = ""
        while i < s.endIndex {
            let remaining = String(s[i...])
            if remaining.hasPrefix(endMarker) {
                i = s.index(i, offsetBy: endMarker.count)
                break
            }
            inner.append(s[i])
            i = s.index(after: i)
        }

        let matrixDelims: [String: (String, String)] = [
            "pmatrix": ("(", ")"),
            "bmatrix": ("[", "]"),
            "Bmatrix": ("{", "}"),
            "vmatrix": ("|", "|"),
            "Vmatrix": ("‖", "‖"),
            "matrix": ("", ""),
            "cases": ("{", ""),
        ]

        if let delims = matrixDelims[envName] {
            let rows = parseMatrixContent(inner)
            return .matrix(rows: rows, open: delims.0, close: delims.1)
        }

        // Unknown environment — parse inner as nodes
        return .row(parse(inner))
    }

    private func parseMatrixContent(_ content: String) -> [[[MathNode]]] {
        let rowStrings = content.components(separatedBy: "\\\\")
        return rowStrings.map { row in
            let cellStrings = row.components(separatedBy: "&")
            return cellStrings.map { cell in
                parse(cell.trimmingCharacters(in: .whitespaces))
            }
        }
    }

    private func readDelimiter(_ s: String, from i: inout String.Index) -> String {
        guard i < s.endIndex else { return "(" }
        if s[i] == "\\" {
            // \{ \} \| etc.
            i = s.index(after: i)
            guard i < s.endIndex else { return "\\" }
            let ch = s[i]
            i = s.index(after: i)
            switch ch {
            case "{": return "{"
            case "}": return "}"
            case "|": return "‖"
            default: return String(ch)
            }
        }
        if s[i] == "." {
            // \left. = invisible delimiter
            i = s.index(after: i)
            return ""
        }
        let ch = String(s[i])
        i = s.index(after: i)
        return ch
    }

    private func handleDelimited(_ s: String, from i: inout String.Index) -> MathNode? {
        guard i < s.endIndex else { return nil }
        let openDelim = readDelimiter(s, from: &i)

        // Parse until \right
        var content: [MathNode] = []
        while i < s.endIndex {
            if s[i] == "\\" {
                let saved = i
                let cmd = readCommand(s, from: &i)
                if cmd == "\\right" {
                    let closeDelim = readDelimiter(s, from: &i)
                    return .delimited(open: openDelim, close: closeDelim, content: content)
                }
                // Not \right, handle normally
                i = saved
                let cmd2 = readCommand(s, from: &i)
                if let node = handleCommand(cmd2, s, from: &i) {
                    content.append(node)
                }
            } else if s[i] == "^" || s[i] == "_" {
                let base = content.isEmpty ? .glyph("") : content.removeLast()
                content.append(readScript(base, s, from: &i))
            } else if s[i] == "{" {
                i = s.index(after: i)
                let inner = parseNodes(s, from: &i, until: "}")
                content.append(contentsOf: inner)
            } else if s[i] == " " {
                i = s.index(after: i)
            } else {
                content.append(.glyph(String(s[i])))
                i = s.index(after: i)
            }
        }
        return .delimited(open: openDelim, close: ")", content: content)
    }

    private func readScript(_ base: MathNode, _ s: String, from i: inout String.Index) -> MathNode {
        var sub: [MathNode]?
        var sup: [MathNode]?

        for _ in 0..<2 {
            skipSpaces(s, from: &i)
            guard i < s.endIndex else { break }
            if s[i] == "_" {
                i = s.index(after: i)
                sub = readScriptArg(s, from: &i)
            } else if s[i] == "^" {
                i = s.index(after: i)
                sup = readScriptArg(s, from: &i)
            }
        }
        return .script(base: base, sub: sub, sup: sup)
    }

    private func maybeScript(_ node: MathNode, _ s: String, from i: inout String.Index) -> MathNode {
        skipSpaces(s, from: &i)
        guard i < s.endIndex && (s[i] == "_" || s[i] == "^") else { return node }
        return readScript(node, s, from: &i)
    }

    private func readScriptArg(_ s: String, from i: inout String.Index) -> [MathNode] {
        skipSpaces(s, from: &i)
        guard i < s.endIndex else { return [] }
        if s[i] == "{" {
            i = s.index(after: i)
            return parseNodes(s, from: &i, until: "}")
        } else if s[i] == "\\" {
            let cmd = readCommand(s, from: &i)
            if let node = handleCommand(cmd, s, from: &i) { return [node] }
            return []
        } else {
            let ch = String(s[i])
            i = s.index(after: i)
            return [.glyph(ch)]
        }
    }

    private func readBraceGroup(_ s: String, from i: inout String.Index) -> [MathNode] {
        skipSpaces(s, from: &i)
        guard i < s.endIndex && s[i] == "{" else { return [] }
        i = s.index(after: i)
        return parseNodes(s, from: &i, until: "}")
    }

    private func readBraceGroupRaw(_ s: String, from i: inout String.Index) -> String {
        skipSpaces(s, from: &i)
        guard i < s.endIndex && s[i] == "{" else { return "" }
        i = s.index(after: i)
        var result = ""
        var depth = 1
        while i < s.endIndex && depth > 0 {
            if s[i] == "{" { depth += 1 }
            if s[i] == "}" { depth -= 1; if depth == 0 { i = s.index(after: i); break } }
            result.append(s[i])
            i = s.index(after: i)
        }
        return result
    }

    private func skipSpaces(_ s: String, from i: inout String.Index) {
        while i < s.endIndex && s[i] == " " { i = s.index(after: i) }
    }
}
