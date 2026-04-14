#if canImport(UIKit)
import XCTest
import UIKit
@testable import SupaNotes

/// Tests for LaTeX validation and corruption detection in the agent feedback loop.
final class LaTeXValidationTests: XCTestCase {

    private let renderer = SwiftMathRenderer()
    private let tokenizer = OverlayTokenizer()

    // MARK: - Corruption Detection

    /// Test that we detect JSON escape corruption where \b becomes backspace.
    /// This simulates: model output: [latex]A = \begin{pmatrix} 1 \\ 1 \end{pmatrix}[/latex]
    /// When JSON-decoded improperly, \b becomes backspace char (0x08).
    func testDetectsBackspaceCorruption() {
        // Simulate corrupted string where \b was decoded as backspace
        let corrupted = "A = \u{08}egin{pmatrix} 1 \\\\ 1 \\end{pmatrix}"

        let result = renderer.validate(latex: corrupted)

        switch result {
        case .corrupted(let msg):
            XCTAssertTrue(msg.contains("control character"), "Should mention control character")
        default:
            XCTFail("Expected .corrupted, got \(result)")
        }
    }

    /// Test that properly escaped pmatrix passes validation.
    func testValidPmatrixPasses() {
        let valid = "A = \\begin{pmatrix} 1 \\\\ 1 \\end{pmatrix}"

        let result = renderer.validate(latex: valid)

        XCTAssertTrue(result.isValid, "Valid pmatrix should pass validation, got: \(result.errorDescription ?? "nil")")
    }

    /// Test full render pipeline with valid pmatrix.
    func testValidPmatrixRenders() {
        let valid = "\\begin{pmatrix} 1 \\\\ 1 \\end{pmatrix}"

        let (renderResult, validation) = renderer.validateAndRender(latex: valid, fontSize: 48)

        XCTAssertTrue(validation.isValid, "Validation should pass")
        XCTAssertNotNil(renderResult, "Should produce render result")
        XCTAssertNotNil(renderResult?.image, "Should produce image")
    }

    // MARK: - Unsupported Command Detection

    func testDetectsUnsupportedMiddle() {
        let latex = "\\left( a \\middle| b \\right)"

        let result = renderer.validate(latex: latex)

        switch result {
        case .unsupported(let cmd):
            XCTAssertEqual(cmd, "\\middle")
        default:
            XCTFail("Expected .unsupported, got \(result)")
        }
    }

    func testDetectsUnsupportedSpacing() {
        let latex = "a \\: b"

        let result = renderer.validate(latex: latex)

        switch result {
        case .unsupported(let cmd):
            XCTAssertEqual(cmd, "\\:")
        default:
            XCTFail("Expected .unsupported, got \(result)")
        }
    }

    // MARK: - Parse Error Detection

    func testDetectsParseError() {
        let latex = "\\begin{pmatrix} 1 \\\\ 1"  // Missing \end

        let result = renderer.validate(latex: latex)

        switch result {
        case .parseError:
            break  // Expected
        default:
            XCTFail("Expected .parseError, got \(result)")
        }
    }

    // MARK: - Tokenizer Integration

    /// Test full pipeline: model output -> tokenize -> validate
    func testTokenizerPipelineWithCorruptedOutput() {
        // Simulate model output with JSON corruption
        let modelOutput = "[latex]A = \u{08}egin{pmatrix} 1 \\\\ 1 \\end{pmatrix}[/latex]"

        let tokens = tokenizer.tokenize(modelOutput)

        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens.first?.type, .latex)

        // Validate the extracted latex
        if let latexToken = tokens.first {
            let result = renderer.validate(latex: latexToken.value)
            XCTAssertFalse(result.isValid, "Corrupted latex should fail validation")

            if case .corrupted = result {
                // Expected
            } else {
                XCTFail("Expected .corrupted, got \(result)")
            }
        }
    }

    /// Test that valid model output passes full pipeline.
    func testTokenizerPipelineWithValidOutput() {
        let modelOutput = "[latex]A = \\begin{pmatrix} 1 \\\\ 1 \\end{pmatrix}[/latex]"

        let tokens = tokenizer.tokenize(modelOutput)

        XCTAssertEqual(tokens.count, 1)

        if let latexToken = tokens.first {
            let (renderResult, validation) = renderer.validateAndRender(
                latex: latexToken.value,
                fontSize: 48
            )
            XCTAssertTrue(validation.isValid, "Valid output should pass: \(validation.errorDescription ?? "")")
            XCTAssertNotNil(renderResult, "Should render successfully")
        }
    }

    // MARK: - Error Message Quality

    func testErrorDescriptionIsUseful() {
        let corrupted = "x = \u{08}eta"  // \beta with corrupted \b

        let result = renderer.validate(latex: corrupted)

        XCTAssertNotNil(result.errorDescription)
        XCTAssertTrue(result.errorDescription?.contains("08") == true, "Should include hex code")
    }

    // MARK: - Exact Model Output Patterns

    /// Test the exact pattern from model output to diagnose rendering issues
    func testExactModelOutputPattern() {
        // Different escaping patterns that might come from model
        let patterns: [(String, String)] = [
            // Double backslash (correct LaTeX row separator)
            ("A = \\begin{pmatrix} 1 \\\\ 1 \\end{pmatrix}", "double backslash"),
            // Single backslash + n (might be interpreted as newline)
            ("A = \\begin{pmatrix} 1 \n 1 \\end{pmatrix}", "literal newline"),
            // Backslash-n as text
            ("A = \\begin{pmatrix} 1 \\n 1 \\end{pmatrix}", "backslash-n"),
        ]

        for (latex, desc) in patterns {
            let validation = renderer.validate(latex: latex)
            let (result, _) = renderer.validateAndRender(latex: latex, fontSize: 48)

            print("Pattern '\(desc)': valid=\(validation.isValid), renders=\(result != nil)")
            print("  Bytes: \(latex.unicodeScalars.map { String(format: "%02X", $0.value) }.joined(separator: " "))")

            if !validation.isValid {
                print("  Error: \(validation.errorDescription ?? "unknown")")
            }
        }

        // The correct pattern should work
        let correct = "A = \\begin{pmatrix} 1 \\\\ 1 \\end{pmatrix}"
        let (result, validation) = renderer.validateAndRender(latex: correct, fontSize: 48)
        XCTAssertTrue(validation.isValid, "Correct pattern should validate")
        XCTAssertNotNil(result, "Correct pattern should render")
    }
}
#endif
