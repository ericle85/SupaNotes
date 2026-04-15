import XCTest
@testable import AgentKit

/// Integration tests — requires Ollama at 100.121.248.31:11434.
/// Run: cd AgentKit && swift test
final class AgentToolTests: XCTestCase {

    // MARK: - Suites
    //
    // Control which modes run via env vars:
    //   swift test                  → both modes
    //   THINKING=on swift test      → thinking ON only
    //   THINKING=off swift test     → thinking OFF only
    //   DISCOVER=1 swift test       → no-think, print missing tools, no accuracy assert

    private static let thinkingEnv = ProcessInfo.processInfo.environment["THINKING"]?.lowercased()
    private static let discoverMode = ProcessInfo.processInfo.environment["DISCOVER"] == "1"

    func testSuite_ThinkingOn() async throws {
        guard !Self.discoverMode, Self.thinkingEnv != "off" else { return }
        try await runSuite(thinking: true)
    }

    func testSuite_ThinkingOff() async throws {
        guard !Self.discoverMode, Self.thinkingEnv != "on" else { return }
        try await runSuite(thinking: false)
    }

    func testSuite_DiscoverTools() async throws {
        guard Self.discoverMode else { return }
        try await discoverMissingTools()
    }

    // MARK: - Cases

    private typealias Case = (topic: String, input: String, check: (String) -> Bool, expected: String, deterministic: Bool)

    private let cases: [Case] = {
        var c: [Case] = []

        // MARK: Arithmetic
        c += [
            ("Arithmetic", "$3 + 5 =$",                     { $0.contains("8") },    "[latex]= 8[/latex]",    true),
            ("Arithmetic", "$10 - 4 =$",                    { $0.contains("6") },    "[latex]6[/latex]",      true),
            ("Arithmetic", "$6 \\times 7 =$",               { $0.contains("42") },   "[latex]= 42[/latex]",   true),
            ("Arithmetic", "$20 \\div 4 =$",                { $0.contains("5") },    "[latex]= 5[/latex]",    true),
            ("Arithmetic", "$7 \\div 2 =$",                 { $0.contains("3.5") },  "[latex]= 3.5[/latex]",  true),
            ("Arithmetic", "$100 - 37 =$",                  { $0.contains("63") },   "[latex]= 63[/latex]",   true),
            ("Arithmetic", "$12 \\times 12 =$",             { $0.contains("144") },  "[latex]= 144[/latex]",  true),
            ("Arithmetic", "$81 \\div 9 =$",                { $0.contains("9") },    "[latex]= 9[/latex]",    true),
            ("Arithmetic", "$2^{10} =$",                    { $0.contains("1024") }, "[latex]= 1024[/latex]", true),
            ("Arithmetic", "$\\sqrt{144} =$",               { $0.contains("12") },   "[latex]= 12[/latex]",   true),
            ("Arithmetic", "$|{-7}| =$",                    { $0.contains("7") },    "[latex]= 7[/latex]",    true),
            ("Arithmetic", "$\\lfloor 3.7 \\rfloor =$",     { $0.contains("3") },    "[latex]= 3[/latex]",    true),
        ]

        // MARK: Fractions
        c += [
            ("Fractions", "$\\frac{1}{2} + \\frac{1}{3} =$",            { $0.contains("5") || $0.contains("6") },       "[latex]\\frac{5}{6}[/latex]",    true),
            ("Fractions", "$\\frac{3}{4} - \\frac{1}{4} =$",            { $0.contains("2") || $0.contains("4") },       "[latex]\\frac{1}{2}[/latex]",    true),
            ("Fractions", "$\\frac{2}{3} \\times \\frac{3}{4} =$",      { $0.contains("1") || $0.contains("2") },       "[latex]\\frac{1}{2}[/latex]",    true),
            ("Fractions", "$\\frac{5}{6} \\div \\frac{5}{3} =$",        { $0.contains("1") || $0.contains("2") },       "[latex]\\frac{1}{2}[/latex]",    true),
            ("Fractions", "$\\frac{7}{4}$ as a mixed number is",         { $0.contains("1") && $0.contains("3") },       "[latex]1\\frac{3}{4}[/latex]",   true),
            ("Fractions", "$0.75 =$",                                    { $0.contains("3") || $0.contains("4") },       "[latex]\\frac{3}{4}[/latex]",    true),
            ("Fractions", "$\\frac{22}{7} \\approx$",                    { $0.contains("3.1") || $0.contains("\\pi") }, "[latex]3.14[/latex]",            true),
        ]

        // MARK: Percentages
        c += [
            ("Percentages", "$25\\% of $200 =$",                     { $0.contains("50") },  "[latex]= 50[/latex]",  true),
            ("Percentages", "$15\\% of $80 =$",                      { $0.contains("12") },  "[latex]= 12[/latex]",  true),
            ("Percentages", "$\\frac{45}{60} =$",                    { $0.contains("75") },  "[latex]75\\%[/latex]", true),
            ("Percentages", "A $10\\%$ increase on $500$ gives",     { $0.contains("550") }, "[latex]550[/latex]",   true),
            ("Percentages", "$200$ increased by $50\\%$ is",         { $0.contains("300") }, "[latex]300[/latex]",   true),
        ]

        // MARK: Algebra - Linear
        c += [
            ("Algebra", "$2x = 10$, so $x =$",              { $0.contains("5") },                              "[latex]x = 5[/latex]",                        true),
            ("Algebra", "$3x + 1 = 10$, so $x =$",          { $0.contains("3") },                              "[latex]x = 3[/latex]",                        true),
            ("Algebra", "$5x - 15 = 0$, so $x =$",          { $0.contains("3") },                              "[latex]x = 3[/latex]",                        true),
            ("Algebra", "$\\frac{x}{4} = 7$, so $x =$",     { $0.contains("28") },                             "[latex]x = 28[/latex]",                       true),
            ("Algebra", "$2x + 3 = 3x - 1$, so $x =$",      { $0.contains("4") },                              "[latex]x = 4[/latex]",                        true),
            ("Algebra", "$y = 2x + 1$, when $x=3$, $y =$",  { $0.contains("7") },                              "[latex]y = 7[/latex]",                        true),
            ("Algebra", "Slope of $y = 3x - 5$ is",         { $0.contains("3") },                              "[latex]3[/latex]",                            true),
            ("Algebra", "y-intercept of $y = 2x + 7$ is",   { $0.contains("7") },                              "[latex]7[/latex]",                            true),
            ("Algebra", "$|x - 3| = 5$, so $x =$",          { $0.contains("8") || $0.contains("-2") },         "[latex]x = 8[/latex] or [latex]x = -2[/latex]", true),
        ]

        // MARK: Algebra - Quadratic
        c += [
            ("Quadratic", "$x^2 - 5x + 6 = 0$, roots are $x =$",       { $0.contains("2") || $0.contains("3") },        "[latex]x = 2, 3[/latex]",  true),
            ("Quadratic", "$x^2 - 9 = 0$, so $x =$",                   { $0.contains("3") },                            "[latex]x = \\pm 3[/latex]", true),
            ("Quadratic", "$x^2 + 4x + 4 = 0$, so $x =$",              { $0.contains("-2") || $0.contains("2") },       "[latex]x = -2[/latex]",    true),
            ("Quadratic", "discriminant of $x^2 - 4x + 3$ is",         { $0.contains("4") },                            "[latex]4[/latex]",         true),
            ("Quadratic", "vertex of $y = x^2 - 2x + 1$ is",           { $0.contains("1") },                            "[latex](1, 0)[/latex]",    true),
            ("Quadratic", "$x^2 + 2x - 8 = 0$, roots are $x =$",       { $0.contains("2") || $0.contains("-4") },       "[latex]x = 2, -4[/latex]", true),
        ]

        // MARK: Polynomials
        c += [
            ("Polynomials", "$(x+2)(x-3) =$",                         { $0.contains("x") },                     "[latex]x^2 - x - 6[/latex]",        false),
            ("Polynomials", "$(a+b)^2 =$",                            { $0.contains("a") && $0.contains("b") }, "[latex]a^2 + 2ab + b^2[/latex]",    false),
            ("Polynomials", "$(a-b)(a+b) =$",                         { $0.contains("a") && $0.contains("b") }, "[latex]a^2 - b^2[/latex]",          false),
            ("Polynomials", "degree of $3x^4 - 2x^2 + 1$ is",        { $0.contains("4") },                     "[latex]4[/latex]",                  true),
            ("Polynomials", "leading coefficient of $-5x^3 + 2x$ is", { $0.contains("-5") || $0.contains("5") }, "[latex]-5[/latex]",               true),
        ]

        // MARK: Geometry
        c += [
            ("Geometry", "Area of a circle with radius $r$ is",          { $0.contains("\\pi") && $0.contains("r") },  "[latex]A = \\pi r^2[/latex]",            false),
            ("Geometry", "Circumference of a circle with radius $r$ is", { $0.contains("\\pi") && $0.contains("r") },  "[latex]C = 2\\pi r[/latex]",             false),
            ("Geometry", "Area of a triangle with base $b$ height $h$",  { $0.contains("b") && $0.contains("h") },     "[latex]A = \\frac{1}{2}bh[/latex]",      false),
            ("Geometry", "Pythagorean theorem: $a^2 + b^2 =$",           { $0.contains("c") },                         "[latex]c^2[/latex]",                     false),
            ("Geometry", "Hypotenuse of 3-4-5 triangle is",              { $0.contains("5") },                         "[latex]5[/latex]",                       true),
            ("Geometry", "Volume of a sphere with radius $r$ is",        { $0.contains("\\pi") && $0.contains("r") },  "[latex]V = \\frac{4}{3}\\pi r^3[/latex]", false),
            ("Geometry", "Area of a rectangle $l \\times w$ is",         { $0.contains("l") || $0.contains("w") },     "[latex]A = lw[/latex]",                  false),
            ("Geometry", "Sum of interior angles of a triangle is",      { $0.contains("180") },                       "[latex]180^\\circ[/latex]",              true),
            ("Geometry", "Sum of interior angles of a hexagon is",       { $0.contains("720") },                       "[latex]720^\\circ[/latex]",              true),
            ("Geometry", "Surface area of a cube with side $s$ is",      { $0.contains("s") },                         "[latex]6s^2[/latex]",                    false),
        ]

        // MARK: Trigonometry
        c += [
            ("Trig", "$\\sin(0) =$",                            { $0.contains("0") },                         "[latex]0[/latex]",                                        true),
            ("Trig", "$\\cos(0) =$",                            { $0.contains("1") },                         "[latex]1[/latex]",                                        true),
            ("Trig", "$\\sin(90^\\circ) =$",                    { $0.contains("1") },                         "[latex]1[/latex]",                                        true),
            ("Trig", "$\\sin^2(\\theta) + \\cos^2(\\theta) =$", { $0.contains("1") },                         "[latex]1[/latex]",                                        true),
            ("Trig", "$\\tan(\\theta) =$",                      { $0.contains("sin") || $0.contains("cos") }, "[latex]\\frac{\\sin\\theta}{\\cos\\theta}[/latex]",        false),
            ("Trig", "$\\sin(30^\\circ) =$",                    { $0.contains("1") || $0.contains("2") },     "[latex]\\frac{1}{2}[/latex]",                             true),
            ("Trig", "$\\cos(60^\\circ) =$",                    { $0.contains("1") || $0.contains("2") },     "[latex]\\frac{1}{2}[/latex]",                             true),
            ("Trig", "$\\sin(45^\\circ) =$",                    { $0.contains("2") },                         "[latex]\\frac{\\sqrt{2}}{2}[/latex]",                     true),
            ("Trig", "Law of cosines: $c^2 =$",                 { $0.contains("a") && $0.contains("b") },     "[latex]a^2 + b^2 - 2ab\\cos C[/latex]",                   false),
        ]

        // MARK: Calculus - Limits
        c += [
            ("Limits", "$\\lim_{x \\to 0} \\frac{\\sin x}{x} =$",   { $0.contains("1") }, "[latex]1[/latex]", true),
            ("Limits", "$\\lim_{x \\to \\infty} \\frac{1}{x} =$",   { $0.contains("0") }, "[latex]0[/latex]", true),
            ("Limits", "$\\lim_{x \\to 2} x^2 =$",                  { $0.contains("4") }, "[latex]4[/latex]", true),
            ("Limits", "$\\lim_{x \\to 0} (1 + x)^{1/x} =$",        { $0.contains("e") }, "[latex]e[/latex]", true),
            ("Limits", "$\\lim_{x \\to \\infty} \\frac{x}{x+1} =$", { $0.contains("1") }, "[latex]1[/latex]", true),
        ]

        // MARK: Calculus - Derivatives
        c += [
            ("Derivatives", "$\\frac{d}{dx} x^3 =$",                    { $0.contains("3") && $0.contains("x") }, "[latex]3x^2[/latex]",                    true),
            ("Derivatives", "$\\frac{d}{dx} x^n =$",                    { $0.contains("n") && $0.contains("x") }, "[latex]nx^{n-1}[/latex]",                false),
            ("Derivatives", "$\\frac{d}{dx} \\sin(x) =$",               { $0.contains("cos") },                   "[latex]\\cos(x)[/latex]",                true),
            ("Derivatives", "$\\frac{d}{dx} \\cos(x) =$",               { $0.contains("sin") },                   "[latex]-\\sin(x)[/latex]",               true),
            ("Derivatives", "$\\frac{d}{dx} e^x =$",                    { $0.contains("e") },                     "[latex]e^x[/latex]",                     true),
            ("Derivatives", "$\\frac{d}{dx} \\ln(x) =$",                { $0.contains("x") },                     "[latex]\\frac{1}{x}[/latex]",            true),
            ("Derivatives", "$\\frac{d}{dx} x^2 + 3x =$",               { $0.contains("2") && $0.contains("x") }, "[latex]2x + 3[/latex]",                  true),
            ("Derivatives", "Product rule: $\\frac{d}{dx} f(x)g(x) =$", { $0.contains("f") && $0.contains("g") }, "[latex]f'g + fg'[/latex]",               false),
            ("Derivatives", "Chain rule: $\\frac{d}{dx} f(g(x)) =$",    { $0.contains("f") && $0.contains("g") }, "[latex]f'(g(x)) \\cdot g'(x)[/latex]",   false),
        ]

        // MARK: Calculus - Integrals
        c += [
            ("Integrals", "$\\int 2x \\, dx =$",              { $0.contains("x") },                     "[latex]x^2 + C[/latex]",                   true),
            ("Integrals", "$\\int x^n \\, dx =$",             { $0.contains("n") && $0.contains("x") }, "[latex]\\frac{x^{n+1}}{n+1} + C[/latex]",  false),
            ("Integrals", "$\\int e^x \\, dx =$",             { $0.contains("e") },                     "[latex]e^x + C[/latex]",                   true),
            ("Integrals", "$\\int \\sin(x) \\, dx =$",        { $0.contains("cos") },                   "[latex]-\\cos(x) + C[/latex]",             true),
            ("Integrals", "$\\int \\cos(x) \\, dx =$",        { $0.contains("sin") },                   "[latex]\\sin(x) + C[/latex]",              true),
            ("Integrals", "$\\int_0^1 x \\, dx =$",           { $0.contains("1") || $0.contains("2") }, "[latex]\\frac{1}{2}[/latex]",              true),
            ("Integrals", "$\\int \\frac{1}{x} \\, dx =$",    { $0.contains("ln") },                    "[latex]\\ln|x| + C[/latex]",               true),
        ]

        // MARK: Statistics
        c += [
            ("Statistics", "Mean of $2, 4, 6, 8, 10$ is",              { $0.contains("6") },  "[latex]6[/latex]",  true),
            ("Statistics", "Median of $1, 3, 5, 7, 9$ is",             { $0.contains("5") },  "[latex]5[/latex]",  true),
            ("Statistics", "Mode of $1, 2, 2, 3, 4$ is",               { $0.contains("2") },  "[latex]2[/latex]",  true),
            ("Statistics", "Range of $3, 7, 2, 9, 1$ is",              { $0.contains("8") },  "[latex]8[/latex]",  true),
            ("Statistics", "Standard deviation formula $\\sigma =$",    { $0.contains("\\sigma") || $0.contains("\\mu") || $0.contains("N") }, "[latex]\\sigma = \\sqrt{\\frac{\\sum(x-\\mu)^2}{N}}[/latex]", false),
            ("Statistics", "Variance is the square of",                  { $0.contains("\\sigma") || $0.contains("deviation") || $0.contains("standard") }, "standard deviation", false),
            ("Statistics", "$P(A \\cup B) =$",                          { $0.contains("P") && $0.contains("A") && $0.contains("B") }, "[latex]P(A) + P(B) - P(A \\cap B)[/latex]", false),
        ]

        // MARK: Linear Algebra
        c += [
            ("Linear Algebra", "$\\det \\begin{bmatrix} 3 & 1 \\\\ 2 & 4 \\end{bmatrix} =$",             { $0.contains("10") || ($0.contains("3") && $0.contains("4") && $0.contains("2")) }, "[latex]10[/latex]",                                            true),
            ("Linear Algebra", "$\\det \\begin{bmatrix} a & b \\\\ c & d \\end{bmatrix} =$",             { $0.contains("a") && $0.contains("d") && $0.contains("b") && $0.contains("c") },     "[latex]ad - bc[/latex]",                                       false),
            ("Linear Algebra", "Transpose of $\\begin{bmatrix} 1 & 2 \\\\ 3 & 4 \\end{bmatrix}$ is",    { $0.contains("1") && $0.contains("3") },                                             "[latex]\\begin{bmatrix} 1 & 3 \\\\ 2 & 4 \\end{bmatrix}[/latex]", true),
            ("Linear Algebra", "Dot product $\\vec{a} \\cdot \\vec{b} =$",                               { $0.contains("a") || $0.contains("b") },                                             "[latex]\\sum a_i b_i[/latex]",                                 false),
            ("Linear Algebra", "An $n \\times n$ matrix is invertible if $\\det \\neq$",                 { $0.contains("0") },                                                                 "[latex]0[/latex]",                                             true),
        ]

        // MARK: Number Theory
        c += [
            ("Number Theory", "$\\gcd(12, 8) =$",              { $0.contains("4") },   "[latex]4[/latex]",                  true),
            ("Number Theory", "$\\text{lcm}(4, 6) =$",         { $0.contains("12") },  "[latex]12[/latex]",                 true),
            ("Number Theory", "$17$ is",                        { $0.contains("prime") || $0.contains("odd") }, "prime",    false),
            ("Number Theory", "$n!$ means",                     { $0.contains("n") || $0.contains("product") || $0.contains("factorial") }, "n factorial", false),
            ("Number Theory", "$0! =$",                         { $0.contains("1") },   "[latex]1[/latex]",                  true),
            ("Number Theory", "Sum of first $n$ natural numbers: $1+2+\\ldots+n =$", { $0.contains("n") }, "[latex]\\frac{n(n+1)}{2}[/latex]", false),
        ]

        // MARK: Probability
        c += [
            ("Probability", "$P(\\text{heads on fair coin}) =$",             { $0.contains("1") || $0.contains("2") },              "[latex]\\frac{1}{2}[/latex]",                 true),
            ("Probability", "$P(A^c) =$",                                    { $0.contains("1") && $0.contains("P") },              "[latex]1 - P(A)[/latex]",                    false),
            ("Probability", "$P(A \\cap B)$ if $A, B$ independent $=$",      { $0.contains("P") && $0.contains("A") && $0.contains("B") }, "[latex]P(A) \\cdot P(B)[/latex]", false),
            ("Probability", "Expected value $E[X] =$",                       { $0.contains("x") || $0.contains("p") || $0.contains("\\mu") }, "[latex]\\sum x_i p_i[/latex]", false),
            ("Probability", "Binomial probability $P(X=k) =$",               { $0.contains("n") && $0.contains("k") },              "[latex]\\binom{n}{k} p^k (1-p)^{n-k}[/latex]", false),
        ]

        return c
    }()

    // MARK: - Discovery

    private func discoverMissingTools() async throws {
        let client = AgentOllamaClient(thinking: false)
        let divider = String(repeating: "-", count: 56)
        var missingTools: [String: [String]] = [:]  // toolName → [inputs that triggered it]

        print("\n\(divider)")
        print("DISCOVER MODE  (thinking OFF)")
        print(divider)

        for c in cases {
            client.clearLog()
            let result = (try? await client.suggest(text: c.input)) ?? "ERROR"
            for entry in client.toolCallLog where entry.hasPrefix("FAIL unknown tool:") {
                let name = String(entry.dropFirst("FAIL unknown tool: ".count)).trimmingCharacters(in: .whitespaces)
                missingTools[name, default: []].append(c.input)
            }
            // Also catch fallback-parsed tools that executed fine but aren't in our list
            for entry in client.toolCallLog where entry.hasPrefix("FALLBACK parse:") {
                let name = String(entry.dropFirst("FALLBACK parse: ".count)).components(separatedBy: "(").first ?? ""
                if !name.isEmpty {
                    // Mark as "auto-handled" so we know to promote it
                    missingTools["[auto] \(name)", default: []].append(c.input)
                }
            }
            print("  \(c.input)  →  \(result)")
        }

        print("\n\(divider)")
        if missingTools.isEmpty {
            print("No missing tools found.")
        } else {
            print("TOOLS TO ADD (\(missingTools.count)):")
            for (tool, inputs) in missingTools.sorted(by: { $0.key < $1.key }) {
                print("  \(tool)")
                inputs.prefix(3).forEach { print("    triggered by: \($0)") }
            }
        }
        print(divider)
    }

    // MARK: - Runner

    private struct CaseResult {
        let topic: String
        let passed: Bool
        let usedTools: Bool
        let elapsed: TimeInterval
        let deterministic: Bool
    }

    private func runSuite(thinking: Bool) async throws {
        let client = AgentOllamaClient(thinking: thinking)
        let mode = thinking ? "thinking ON" : "thinking OFF"
        let divider = String(repeating: "-", count: 56)
        var results: [CaseResult] = []
        var currentTopic = ""

        print("\n\(divider)")
        print("MODE: \(mode)")
        print(divider)

        for c in cases {
            if c.topic != currentTopic {
                currentTopic = c.topic
                print("\n  [\(currentTopic)]")
            }

            client.clearLog()
            let start = Date()
            let result: String
            do {
                result = try await client.suggest(text: c.input)
            } catch {
                let elapsed = Date().timeIntervalSince(start)
                print("ERROR \(c.input)")
                print("      error : \(error.localizedDescription)  [\(String(format: "%.2f", elapsed))s]")
                results.append(CaseResult(topic: c.topic, passed: false, usedTools: false, elapsed: elapsed, deterministic: c.deterministic))
                continue
            }
            let elapsed = Date().timeIntervalSince(start)
            let passed = c.check(result)
            let usedTools = !client.toolCallLog.isEmpty
            results.append(CaseResult(topic: c.topic, passed: passed, usedTools: usedTools, elapsed: elapsed, deterministic: c.deterministic))

            if passed {
                let toolNote = usedTools ? client.toolCallLog.joined(separator: ", ") : "no tools"
                print("\tPASS  \(c.input)")
                print("\t      output : \(result)")
                print("\t      tools  : \(toolNote)  [\(String(format: "%.2f", elapsed))s]")
            } else {
                print("FAIL  \(c.input)")
                print("      expected : \(c.expected)")
                print("      output   : \(result)")
                let toolNote = usedTools ? client.toolCallLog.joined(separator: ", ") : "none"
                print("      tools    : \(toolNote)  [\(String(format: "%.2f", elapsed))s]")
            }
        }

        let passed    = results.filter { $0.passed }.count
        let total     = results.count
        let toolRate  = results.filter { $0.usedTools }.count
        let totalTime = results.map { $0.elapsed }.reduce(0, +)
        let avgTime   = totalTime / Double(total)
        let accuracy  = Double(passed) / Double(total) * 100

        let detResults = results.filter { $0.deterministic }
        let detPassed  = detResults.filter { $0.passed }.count
        let detTotal   = detResults.count
        let detAccuracy = detTotal > 0 ? Double(detPassed) / Double(detTotal) * 100 : 0

        print("\n\(divider)")
        print(String(format: "accuracy  : %d/%d  (%.0f%%)", passed, total, accuracy))
        print(String(format: "det. only : %d/%d  (%.0f%%)  [deterministic cases]", detPassed, detTotal, detAccuracy))
        print(String(format: "tool use  : %d/%d cases", toolRate, total))
        print(String(format: "time      : %.2fs total  /  %.2fs avg", totalTime, avgTime))

        // Per-topic breakdown
        let topics = cases.map { $0.topic }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        print("\n  per topic:")
        for topic in topics {
            let topicResults = results.filter { $0.topic == topic }
            let tp = topicResults.filter { $0.passed }.count
            print(String(format: "    %-20s %d/%d", (topic as NSString).utf8String!, tp, topicResults.count))
        }
        print(divider)

        XCTAssertEqual(passed, total, "\(total - passed) case(s) failed in mode: \(mode)")
    }
}
