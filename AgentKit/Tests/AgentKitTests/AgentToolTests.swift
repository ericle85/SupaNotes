import XCTest
@testable import AgentKit

/// Integration tests — requires Ollama at 100.121.248.31:11434.
/// Run: cd AgentKit && swift test
final class AgentToolTests: XCTestCase {

    // MARK: - Test Suites

    func testSuite_ThinkingOn() async throws {
        try await runSuite(thinking: true)
    }

    func testSuite_ThinkingOff() async throws {
        try await runSuite(thinking: false)
    }

    // MARK: - Cases

    private typealias Case = (input: String, check: (String) -> Bool, expected: String)

    private let cases: [Case] = [
        ("$3 + 5 =$",                                                    { $0.contains("8") },                     "8"),
        ("$10 - 4 =$",                                                   { $0.contains("6") },                     "6"),
        ("$6 \\times 7 =$",                                              { $0.contains("42") },                    "42"),
        ("$20 \\div 4 =$",                                               { $0.contains("5") },                     "5"),
        ("$7 \\div 2 =$",                                                { $0.contains("3.5") },                   "3.5"),
        ("$2x = 10$, so $x =$",                                          { $0.contains("5") },                     "5"),
        ("$x^2 - 5x + 6 = 0$, roots are $x =$",                         { $0.contains("2") || $0.contains("3") }, "2 or 3"),
        ("$\\frac{d}{dx} x^3 =$",                                        { $0.contains("3") && $0.contains("x") }, "3x^2"),
        ("$\\int 2x \\, dx =$",                                          { $0.contains("x") },                     "x^2 + C"),
        ("$\\det \\begin{bmatrix} 3 & 1 \\\\ 2 & 4 \\end{bmatrix} =$",  { $0.contains("10") },                    "10"),
    ]

    // MARK: - Runner

    private struct CaseResult {
        let passed: Bool
        let usedTools: Bool
        let elapsed: TimeInterval
    }

    private func runSuite(thinking: Bool) async throws {
        let client = AgentOllamaClient(thinking: thinking)
        let mode = thinking ? "thinking ON" : "thinking OFF"
        let divider = String(repeating: "-", count: 56)
        var results: [CaseResult] = []

        print("\n\(divider)")
        print("MODE: \(mode)")
        print(divider)

        for c in cases {
            client.clearLog()
            let start = Date()
            let result = try await client.suggest(text: c.input)
            let elapsed = Date().timeIntervalSince(start)
            let passed = c.check(result)
            let usedTools = !client.toolCallLog.isEmpty
            results.append(CaseResult(passed: passed, usedTools: usedTools, elapsed: elapsed))

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

        let passed   = results.filter { $0.passed }.count
        let total    = results.count
        let toolRate = results.filter { $0.usedTools }.count
        let totalTime = results.map { $0.elapsed }.reduce(0, +)
        let avgTime   = totalTime / Double(total)
        let accuracy  = Double(passed) / Double(total) * 100

        print(divider)
        print(String(format: "accuracy  : %d/%d  (%.0f%%)", passed, total, accuracy))
        print(String(format: "tool use  : %d/%d cases", toolRate, total))
        print(String(format: "time      : %.2fs total  /  %.2fs avg", totalTime, avgTime))
        print(divider)

        XCTAssert(passed == total, "\(total - passed) case(s) failed in mode: \(mode)")
    }
}
