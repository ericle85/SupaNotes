import Foundation
import CoreGraphics

enum OverlayTokenType: String, Codable {
    case latex
    case word
}

struct OverlayToken: Identifiable {
    let id = UUID()
    let type: OverlayTokenType
    let value: String      // raw content for matching
    let displayLatex: String // for rendering (words wrapped in \text{})
}

/// A single visible character/symbol in the overlay with its bounding box.
struct OverlayCharacter: Identifiable {
    let id: String         // "c-0", "c-1", etc.
    let index: Int
    let displayLatex: String // KaTeX-renderable string for this character
    let sourceToken: OverlayTokenType
    var rect: CGRect = .zero
    var state: CharacterState = .pending

    enum CharacterState {
        case pending   // ghost visible
        case accepted  // fading up
        case rejected  // fading down
    }
}

/// Result of atomization: characters + renderable LaTeX with embedded \htmlId tags.
struct AtomizeResult {
    let characters: [OverlayCharacter]
    let renderableLatex: String
}

/// Splits tokens into individual renderable atoms for per-character bounding boxes.
struct OverlayAtomizer {
    /// Atomize tokens and produce both character list and renderable LaTeX.
    func atomizeWithLatex(_ tokens: [OverlayToken]) -> AtomizeResult {
        var chars: [OverlayCharacter] = []
        var latexParts: [String] = []
        var idx = 0

        for token in tokens {
            switch token.type {
            case .word:
                for ch in token.value {
                    let charId = "c-\(idx)"
                    chars.append(OverlayCharacter(
                        id: charId, index: idx,
                        displayLatex: "\\text{\(ch)}",
                        sourceToken: .word
                    ))
                    latexParts.append("\\htmlId{\(charId)}{\\text{\(ch)}}")
                    idx += 1
                }
                latexParts.append("\\;")

            case .latex:
                let tagged = tagLatexAtoms(token.value, startIndex: &idx, chars: &chars)
                latexParts.append(tagged)
            }
        }

        // Remove trailing space
        if latexParts.last == "\\;" { latexParts.removeLast() }
        if let last = chars.last, last.displayLatex == "\\;" { chars.removeLast() }

        return AtomizeResult(characters: chars, renderableLatex: latexParts.joined())
    }

    /// Walk LaTeX, wrapping each visual atom with \htmlId while keeping structure intact.
    private func tagLatexAtoms(_ latex: String, startIndex idx: inout Int, chars: inout [OverlayCharacter]) -> String {
        var result = ""
        var i = latex.startIndex

        while i < latex.endIndex {
            let ch = latex[i]

            if ch == "\\" {
                var cmd = "\\"
                i = latex.index(after: i)
                if i < latex.endIndex && !latex[i].isLetter {
                    cmd.append(latex[i])
                    i = latex.index(after: i)
                    if cmd == "\\;" || cmd == "\\," || cmd == "\\!" || cmd == "\\ " || cmd == "\\\\" {
                        result += cmd
                        continue
                    }
                    let charId = "c-\(idx)"
                    chars.append(OverlayCharacter(id: charId, index: idx, displayLatex: cmd, sourceToken: .latex))
                    result += "\\htmlId{\(charId)}{\(cmd)}"
                    idx += 1
                    continue
                }
                while i < latex.endIndex && latex[i].isLetter {
                    cmd.append(latex[i])
                    i = latex.index(after: i)
                }

                if cmd == "\\begin" {
                    let envArg = consumeBraceGroup(latex, from: &i)
                    let envName = String(envArg.dropFirst().dropLast())
                    let endMarker = "\\end{\(envName)}"
                    var inner = ""
                    while i < latex.endIndex {
                        let remaining = String(latex[i...])
                        if remaining.hasPrefix(endMarker) {
                            i = latex.index(i, offsetBy: endMarker.count)
                            break
                        }
                        inner.append(latex[i])
                        i = latex.index(after: i)
                    }

                    let matrixEnvs: Set<String> = ["pmatrix", "bmatrix", "Bmatrix", "vmatrix", "Vmatrix", "matrix"]
                    if matrixEnvs.contains(envName) {
                        // Rebuild matrix with \htmlId on each cell
                        let rows = inner.components(separatedBy: "\\\\")
                        var taggedRows: [String] = []
                        for row in rows {
                            let cells = row.components(separatedBy: "&")
                            var taggedCells: [String] = []
                            for cell in cells {
                                let trimmed = cell.trimmingCharacters(in: .whitespaces)
                                if !trimmed.isEmpty {
                                    taggedCells.append(tagLatexAtoms(trimmed, startIndex: &idx, chars: &chars))
                                }
                            }
                            taggedRows.append(taggedCells.joined(separator: " & "))
                        }
                        result += "\\begin{\(envName)}" + taggedRows.joined(separator: " \\\\ ") + "\\end{\(envName)}"
                    } else {
                        // Unknown env — tag whole thing as one atom
                        let charId = "c-\(idx)"
                        let full = "\\begin{\(envName)}" + inner + "\\end{\(envName)}"
                        chars.append(OverlayCharacter(id: charId, index: idx, displayLatex: full, sourceToken: .latex))
                        result += "\\htmlId{\(charId)}{\(full)}"
                        idx += 1
                    }

                } else if cmd == "\\left" || cmd == "\\right" {
                    if i < latex.endIndex {
                        cmd.append(latex[i])
                        i = latex.index(after: i)
                    }
                    result += cmd // delimiters can't be wrapped in \htmlId easily
                } else if compoundCommands.contains(cmd) {
                    // \frac, \sum, \sqrt etc. — wrap entire compound as one atom
                    let argCount = commandArgCounts[cmd] ?? 0
                    for _ in 0..<argCount {
                        cmd += consumeBraceGroup(latex, from: &i)
                    }
                    cmd += consumeScripts(latex, from: &i)
                    let charId = "c-\(idx)"
                    chars.append(OverlayCharacter(id: charId, index: idx, displayLatex: cmd, sourceToken: .latex))
                    result += "\\htmlId{\(charId)}{\(cmd)}"
                    idx += 1
                } else if cmd == "\\text" || cmd == "\\mathrm" || cmd == "\\mathbf" {
                    cmd += consumeBraceGroup(latex, from: &i)
                    let charId = "c-\(idx)"
                    chars.append(OverlayCharacter(id: charId, index: idx, displayLatex: cmd, sourceToken: .latex))
                    result += "\\htmlId{\(charId)}{\(cmd)}"
                    idx += 1
                } else {
                    // Single glyph command + optional scripts
                    cmd += consumeScripts(latex, from: &i)
                    let charId = "c-\(idx)"
                    chars.append(OverlayCharacter(id: charId, index: idx, displayLatex: cmd, sourceToken: .latex))
                    result += "\\htmlId{\(charId)}{\(cmd)}"
                    idx += 1
                }

            } else if ch == "{" || ch == "}" {
                result.append(ch) // preserve grouping
                i = latex.index(after: i)
            } else if ch == "^" || ch == "_" {
                // Script attached to previous — tricky with htmlId already emitted
                // Just emit the script structure, KaTeX will attach to previous
                result.append(ch)
                i = latex.index(after: i)
                if i < latex.endIndex && latex[i] == "{" {
                    result += consumeBraceGroup(latex, from: &i)
                } else if i < latex.endIndex {
                    result.append(latex[i])
                    i = latex.index(after: i)
                }
            } else if ch == " " {
                i = latex.index(after: i)
            } else {
                let charId = "c-\(idx)"
                chars.append(OverlayCharacter(id: charId, index: idx, displayLatex: String(ch), sourceToken: .latex))
                result += "\\htmlId{\(charId)}{\(ch)}"
                idx += 1
                i = latex.index(after: i)
            }
        }

        return result
    }

    func atomize(_ tokens: [OverlayToken]) -> [OverlayCharacter] {
        var chars: [OverlayCharacter] = []
        var idx = 0

        for token in tokens {
            switch token.type {
            case .word:
                // Each letter is its own character
                for ch in token.value {
                    chars.append(OverlayCharacter(
                        id: "c-\(idx)",
                        index: idx,
                        displayLatex: "\\text{\(ch)}",
                        sourceToken: .word
                    ))
                    idx += 1
                }
                // Space after word
                chars.append(OverlayCharacter(
                    id: "c-\(idx)",
                    index: idx,
                    displayLatex: "\\;",
                    sourceToken: .word
                ))
                idx += 1

            case .latex:
                // Split LaTeX into individual atoms
                let atoms = splitLatexAtoms(token.value)
                for atom in atoms {
                    chars.append(OverlayCharacter(
                        id: "c-\(idx)",
                        index: idx,
                        displayLatex: atom,
                        sourceToken: .latex
                    ))
                    idx += 1
                }
            }
        }

        // Remove trailing space if present
        if let last = chars.last, last.displayLatex == "\\;" {
            chars.removeLast()
        }

        return chars
    }

    /// Split a LaTeX expression into individual visual atoms.
    /// Compound structures (\sum with limits, \frac, \sqrt, \left/\right) stay as one atom.
    /// Simple characters (letters, digits, operators) are individual atoms.
    private func splitLatexAtoms(_ latex: String) -> [String] {
        var atoms: [String] = []
        var i = latex.startIndex

        while i < latex.endIndex {
            let ch = latex[i]

            if ch == "\\" {
                var cmd = "\\"
                i = latex.index(after: i)
                // Single non-alpha char commands
                if i < latex.endIndex && !latex[i].isLetter {
                    cmd.append(latex[i])
                    i = latex.index(after: i)
                    if cmd == "\\;" || cmd == "\\," || cmd == "\\!" || cmd == "\\ " {
                        continue // skip spacing
                    }
                    atoms.append(cmd)
                    continue
                }
                // Collect command name
                while i < latex.endIndex && latex[i].isLetter {
                    cmd.append(latex[i])
                    i = latex.index(after: i)
                }

                if cmd == "\\begin" {
                    // \begin{env}...\end{env}
                    let envArg = consumeBraceGroup(latex, from: &i)
                    let envName = String(envArg.dropFirst().dropLast())
                    let endMarker = "\\end{\(envName)}"

                    // Collect inner content
                    var inner = ""
                    while i < latex.endIndex {
                        let remaining = String(latex[i...])
                        if remaining.hasPrefix(endMarker) {
                            i = latex.index(i, offsetBy: endMarker.count)
                            break
                        }
                        inner.append(latex[i])
                        i = latex.index(after: i)
                    }

                    // Matrix-like envs: split into delimiters + cell entries
                    let matrixEnvs: [String: (String, String)] = [
                        "pmatrix": ("(", ")"),
                        "bmatrix": ("[", "]"),
                        "Bmatrix": ("\\{", "\\}"),
                        "vmatrix": ("|", "|"),
                        "Vmatrix": ("\\|", "\\|"),
                    ]

                    if let delims = matrixEnvs[envName] {
                        atoms.append(delims.0) // opening delimiter
                        // Split cells by & and \\
                        let rows = inner.components(separatedBy: "\\\\")
                        for row in rows {
                            let cells = row.components(separatedBy: "&")
                            for cell in cells {
                                let trimmed = cell.trimmingCharacters(in: .whitespaces)
                                if !trimmed.isEmpty {
                                    atoms.append(contentsOf: splitLatexAtoms(trimmed))
                                }
                            }
                        }
                        atoms.append(delims.1) // closing delimiter
                    } else if envName == "matrix" {
                        // bare matrix — no delimiters
                        let rows = inner.components(separatedBy: "\\\\")
                        for row in rows {
                            let cells = row.components(separatedBy: "&")
                            for cell in cells {
                                let trimmed = cell.trimmingCharacters(in: .whitespaces)
                                if !trimmed.isEmpty {
                                    atoms.append(contentsOf: splitLatexAtoms(trimmed))
                                }
                            }
                        }
                    } else {
                        // Unknown env — keep as one atom
                        atoms.append("\\begin{\(envName)}" + inner + "\\end{\(envName)}")
                    }
                } else if compoundCommands.contains(cmd) {
                    // Compound: consume all arguments + trailing sub/superscripts as one atom
                    let argCount = commandArgCounts[cmd] ?? 0
                    for _ in 0..<argCount {
                        cmd += consumeBraceGroup(latex, from: &i)
                    }
                    // Consume trailing sub/superscripts (e.g. \sum_{...}^{...})
                    cmd += consumeScripts(latex, from: &i)
                    atoms.append(cmd)
                } else if cmd == "\\left" || cmd == "\\right" {
                    // \left( or \right) — consume the delimiter char
                    if i < latex.endIndex {
                        cmd.append(latex[i])
                        i = latex.index(after: i)
                    }
                    atoms.append(cmd)
                } else if cmd == "\\text" || cmd == "\\mathrm" || cmd == "\\mathbf" {
                    // Text commands — consume arg, keep as one atom
                    cmd += consumeBraceGroup(latex, from: &i)
                    atoms.append(cmd)
                } else {
                    // Single-glyph commands: \pi, \alpha, \infty, etc.
                    // Check for trailing scripts: \pi^{2} stays as one atom
                    cmd += consumeScripts(latex, from: &i)
                    atoms.append(cmd)
                }

            } else if ch == "{" || ch == "}" {
                i = latex.index(after: i)
            } else if ch == "^" || ch == "_" {
                // Bare script not attached to a command — attach to previous atom
                if !atoms.isEmpty {
                    var prev = atoms.removeLast()
                    prev.append(ch)
                    prev += consumeScriptArg(latex, from: &i)
                    // Check for second script
                    prev += consumeScripts(latex, from: &i)
                    atoms.append(prev)
                } else {
                    i = latex.index(after: i)
                }
            } else if ch == " " {
                i = latex.index(after: i)
            } else {
                // Regular character
                atoms.append(String(ch))
                i = latex.index(after: i)
            }
        }

        return atoms
    }

    // MARK: - Parsing Helpers

    /// Commands that form compound visual units with their arguments and scripts.
    private let compoundCommands: Set<String> = [
        "\\frac", "\\dfrac", "\\tfrac",
        "\\sqrt",
        "\\sum", "\\prod", "\\int", "\\oint",
        "\\lim", "\\max", "\\min", "\\sup", "\\inf",
        "\\binom",
        // \\begin/\\end handled separately above
        "\\overline", "\\underline", "\\hat", "\\bar", "\\vec", "\\dot", "\\ddot", "\\tilde",
    ]

    private let commandArgCounts: [String: Int] = [
        "\\frac": 2, "\\dfrac": 2, "\\tfrac": 2, "\\binom": 2,
        "\\sqrt": 1,
        "\\overline": 1, "\\underline": 1, "\\hat": 1, "\\bar": 1,
        "\\vec": 1, "\\dot": 1, "\\ddot": 1, "\\tilde": 1,
    ]

    /// Consume a `{...}` group including braces. Returns "" if no brace found.
    private func consumeBraceGroup(_ s: String, from i: inout String.Index) -> String {
        guard i < s.endIndex && s[i] == "{" else { return "" }
        var result = ""
        var depth = 0
        while i < s.endIndex {
            if s[i] == "{" { depth += 1 }
            if s[i] == "}" { depth -= 1 }
            result.append(s[i])
            i = s.index(after: i)
            if depth == 0 { break }
        }
        return result
    }

    /// Consume trailing `_{}` and/or `^{}` scripts. Returns combined string.
    private func consumeScripts(_ s: String, from i: inout String.Index) -> String {
        var result = ""
        // Up to 2 scripts (sub + super in any order)
        for _ in 0..<2 {
            // Skip spaces
            while i < s.endIndex && s[i] == " " { i = s.index(after: i) }
            guard i < s.endIndex && (s[i] == "_" || s[i] == "^") else { break }
            result.append(s[i])
            result += consumeScriptArg(s, from: &i)
        }
        return result
    }

    /// Consume a script marker and its argument: `_X` or `_{...}`.
    /// Assumes `i` points at `_` or `^`. Advances past the marker.
    private func consumeScriptArg(_ s: String, from i: inout String.Index) -> String {
        guard i < s.endIndex && (s[i] == "_" || s[i] == "^") else { return "" }
        i = s.index(after: i) // skip _ or ^
        if i < s.endIndex && s[i] == "{" {
            return consumeBraceGroup(s, from: &i)
        } else if i < s.endIndex {
            let ch = String(s[i])
            i = s.index(after: i)
            return ch
        }
        return ""
    }
}
