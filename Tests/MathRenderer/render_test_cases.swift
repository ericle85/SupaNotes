#if canImport(UIKit)
import XCTest
import UIKit
@testable import SupaNotes

/// Visual test suite for MathLayoutEngine.
/// Renders LaTeX cases to PNG images in Tests/MathRenderer/output/ for manual review.
final class MathRendererTests: XCTestCase {

    private let outputDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("output")

    private let cleanOutputDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("output_clean")

    private let parser = MathParser()
    private let engine = MathLayoutEngine()
    private let fontSize: CGFloat = 48

    override func setUp() {
        super.setUp()
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: cleanOutputDir, withIntermediateDirectories: true)
    }

    // MARK: - Basic

    func testSimpleNumber() {
        renderCase("= 6", name: "simple_number")
    }

    func testSimpleExpression() {
        renderCase("x + 3 = 7", name: "simple_expression")
    }

    func testMultiplication() {
        renderCase("2 \\times 3 = 6", name: "multiplication")
    }

    func testNegative() {
        renderCase("-5 + 3 = -2", name: "negative")
    }

    // MARK: - Fractions

    func testSimpleFraction() {
        renderCase("\\frac{1}{2}", name: "fraction_simple")
    }

    func testFractionInExpression() {
        renderCase("x = \\frac{a + b}{c}", name: "fraction_in_expr")
    }

    func testNestedFraction() {
        renderCase("\\frac{\\frac{1}{2}}{3}", name: "fraction_nested")
    }

    func testFractionWithVariables() {
        renderCase("\\frac{dy}{dx}", name: "fraction_derivative")
    }

    // MARK: - Subscripts & Superscripts

    func testSuperscript() {
        renderCase("x^{2}", name: "superscript")
    }

    func testSubscript() {
        renderCase("a_{n}", name: "subscript")
    }

    func testBothScripts() {
        renderCase("x_{i}^{2}", name: "both_scripts")
    }

    func testChainedExponent() {
        renderCase("e^{i \\pi}", name: "euler_exponent")
    }

    // MARK: - Summation & Products

    func testSummation() {
        renderCase("\\sum_{n=0}^{\\infty} a_{n}", name: "summation")
    }

    func testProduct() {
        renderCase("\\prod_{i=1}^{n} x_{i}", name: "product")
    }

    func testSummationFraction() {
        renderCase("\\sum_{n=1}^{\\infty} \\frac{1}{n^{2}}", name: "summation_fraction")
    }

    // MARK: - Integrals

    func testIntegral() {
        renderCase("\\int_{0}^{1} x^{2} dx", name: "integral")
    }

    func testIntegralFraction() {
        renderCase("\\int \\frac{1}{x} dx", name: "integral_fraction")
    }

    func testGaussianIntegral() {
        renderCase("\\int_{-\\infty}^{\\infty} e^{-x^{2}} dx = \\sqrt{\\pi}", name: "gaussian_integral")
    }

    func testDoubleIntegral() {
        renderCase("\\int \\int_{D} f(x, y) dA", name: "double_integral")
    }

    func testIntegralMatrix() {
        renderCase("\\int_{0}^{1} \\begin{pmatrix} t \\\\ t^{2} \\end{pmatrix} dt", name: "integral_matrix")
    }

    // MARK: - Limits

    func testLimit() {
        renderCase("\\lim_{x \\to 0} \\frac{\\sin x}{x}", name: "limit")
    }

    // MARK: - Square Roots

    func testSqrt() {
        renderCase("\\sqrt{x}", name: "sqrt_simple")
    }

    func testSqrtExpression() {
        renderCase("\\sqrt{a^{2} + b^{2}}", name: "sqrt_expression")
    }

    func testSqrtFraction() {
        renderCase("\\sqrt{\\frac{1}{2}}", name: "sqrt_fraction")
    }

    // MARK: - Matrices

    func testMatrix2x1() {
        renderCase("\\begin{pmatrix} 4 \\\\ 2 \\end{pmatrix}", name: "matrix_2x1")
    }

    func testMatrix2x2() {
        renderCase("\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}", name: "matrix_2x2")
    }

    func testBracketMatrix() {
        renderCase("\\begin{bmatrix} 1 & 0 \\\\ 0 & 1 \\end{bmatrix}", name: "matrix_bracket")
    }

    func testMatrixMultiplication() {
        renderCase("A = \\begin{pmatrix} 1 & 2 \\\\ 3 & 4 \\end{pmatrix}", name: "matrix_with_var")
    }

    func testDeterminant() {
        renderCase("\\det \\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix} = ad - bc", name: "determinant")
    }

    func testNullspace() {
        renderCase("N(A) = \\left\\{ \\vec{x} \\in \\mathbb{R}^{n} : A\\vec{x} = \\vec{0} \\right\\}", name: "nullspace")
    }

    func testSystemOfEquations() {
        renderCase("\\begin{cases} 2x + 3y = 7 \\\\ x - y = 1 \\end{cases}", name: "system_of_equations")
    }

    func testSystemOfEquations3() {
        renderCase("\\begin{cases} x + y + z = 6 \\\\ 2x - y = 1 \\\\ x + z = 4 \\end{cases}", name: "system_3_equations")
    }

    func testSpan() {
        renderCase("\\operatorname{span} \\left\\{ \\vec{v}_{1}, \\vec{v}_{2} \\right\\}", name: "span")
    }

    // MARK: - Greek Letters

    func testGreekLetters() {
        renderCase("\\alpha + \\beta = \\gamma", name: "greek_letters")
    }

    func testGreekExpression() {
        renderCase("\\Delta x = x_{1} - x_{0}", name: "greek_delta")
    }

    // MARK: - Accents

    func testVec() {
        renderCase("\\vec{v}", name: "accent_vec")
    }

    func testHat() {
        renderCase("\\hat{x}", name: "accent_hat")
    }

    func testBar() {
        renderCase("\\bar{x}", name: "accent_bar")
    }

    func testOverline() {
        renderCase("\\overline{AB}", name: "accent_overline")
    }

    func testDot() {
        renderCase("\\dot{x}", name: "accent_dot")
    }

    func testTilde() {
        renderCase("\\tilde{x}", name: "accent_tilde")
    }

    // MARK: - Delimiters

    func testParentheses() {
        renderCase("\\left( x + 1 \\right)", name: "delimited_parens")
    }

    func testBrackets() {
        renderCase("\\left[ a, b \\right]", name: "delimited_brackets")
    }

    // MARK: - Mixed Text + Math

    func testMixedTextMath() {
        renderMixed(
            tokens: [
                OverlayToken(type: .word, value: "where", displayLatex: "\\text{where}"),
                OverlayToken(type: .latex, value: "x = \\frac{1}{2}", displayLatex: "x = \\frac{1}{2}"),
            ],
            name: "mixed_text_math"
        )
    }

    func testMixedSentence() {
        renderMixed(
            tokens: [
                OverlayToken(type: .word, value: "the", displayLatex: "\\text{the}"),
                OverlayToken(type: .word, value: "limit", displayLatex: "\\text{limit}"),
                OverlayToken(type: .word, value: "is", displayLatex: "\\text{is}"),
                OverlayToken(type: .latex, value: "\\infty", displayLatex: "\\infty"),
            ],
            name: "mixed_sentence"
        )
    }

    // MARK: - Complex Expressions

    func testQuadraticFormula() {
        renderCase("x = \\frac{-b \\pm \\sqrt{b^{2} - 4ac}}{2a}", name: "quadratic_formula")
    }

    func testTaylorSeries() {
        renderCase("\\sum_{n=0}^{\\infty} \\frac{f^{(n)}(a)}{n!} (x - a)^{n}", name: "taylor_series")
    }

    func testEulerIdentity() {
        renderCase("e^{i\\pi} + 1 = 0", name: "euler_identity")
    }

    func testPythagorean() {
        renderCase("a^{2} + b^{2} = c^{2}", name: "pythagorean")
    }

    // MARK: - Helpers

    private func renderCase(_ latex: String, name: String) {
        let nodes = parser.parse(latex)

        let withBoxes = engine.layout(nodes: nodes, fontSize: fontSize, drawDebugBoxes: true)
        saveImage(withBoxes.image, dir: outputDir, name: name, latex: latex, charCount: withBoxes.characters.count)

        let clean = engine.layout(nodes: nodes, fontSize: fontSize, drawDebugBoxes: false)
        saveImage(clean.image, dir: cleanOutputDir, name: name, latex: latex, charCount: clean.characters.count)
    }

    private func renderMixed(tokens: [OverlayToken], name: String) {
        var allNodes: [MathNode] = []
        for token in tokens {
            switch token.type {
            case .latex:
                allNodes.append(contentsOf: parser.parse(token.value))
            case .word:
                allNodes.append(.text(token.value))
                allNodes.append(.space)
            }
        }
        let latex = tokens.map(\.value).joined(separator: " ")

        let withBoxes = engine.layout(nodes: allNodes, fontSize: fontSize, drawDebugBoxes: true)
        saveImage(withBoxes.image, dir: outputDir, name: name, latex: latex, charCount: withBoxes.characters.count)

        let clean = engine.layout(nodes: allNodes, fontSize: fontSize, drawDebugBoxes: false)
        saveImage(clean.image, dir: cleanOutputDir, name: name, latex: latex, charCount: clean.characters.count)
    }

    private func saveImage(_ image: UIImage, dir: URL, name: String, latex: String, charCount: Int) {
        // Composite onto white background
        let renderer = UIGraphicsImageRenderer(size: image.size)
        let whiteImage = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: image.size))
            image.draw(at: .zero)
        }

        let url = dir.appendingPathComponent("\(name).png")
        if let data = whiteImage.pngData() {
            try? data.write(to: url)
            print("[\(name)] \(charCount) chars | \(latex) → \(url.lastPathComponent)")
        }
        XCTAssertNotNil(image, "\(name) should produce an image")
    }
}
#endif
