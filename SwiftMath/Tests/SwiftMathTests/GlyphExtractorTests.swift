import XCTest
@testable import SwiftMath
import CoreText
import CoreGraphics

final class GlyphExtractorTests: XCTestCase {

    private let fontSize: CGFloat = 48

    // MARK: - Helpers

    private func displayList(for latex: String) -> MTMathListDisplay? {
        let label = MTMathUILabel()
        label.latex = latex
        label.fontSize = fontSize
        label.labelMode = .display
        label.frame = CGRect(x: 0, y: 0, width: 2000, height: 2000)
        #if os(macOS)
        label.layout()
        #else
        label.setNeedsLayout()
        label.layoutIfNeeded()
        #endif
        guard let dl = label.displayList else { return nil }
        dl.position = .zero
        return dl
    }

    private func glyphRects(for latex: String) -> [GlyphRect] {
        guard let dl = displayList(for: latex) else { return [] }
        return extractGlyphRects(from: dl)
    }

    // MARK: - Basic expressions

    func testSingleVariable() {
        let rects = glyphRects(for: "x")
        XCTAssertEqual(rects.count, 1, "Single variable should produce 1 glyph")
        XCTAssertGreaterThan(rects[0].rect.width, 0)
        XCTAssertGreaterThan(rects[0].rect.height, 0)
    }

    func testSingleDigit() {
        let rects = glyphRects(for: "5")
        XCTAssertEqual(rects.count, 1)
        XCTAssertGreaterThan(rects[0].rect.width, 0)
    }

    func testMultipleVariables() {
        let rects = glyphRects(for: "abc")
        XCTAssertEqual(rects.count, 3, "Three variables should produce 3 glyphs")
        // Glyphs should be left-to-right ordered
        for i in 1..<rects.count {
            XCTAssertGreaterThan(rects[i].rect.minX, rects[i-1].rect.minX,
                                 "Glyphs should be ordered left to right")
        }
    }

    func testSimpleAddition() {
        let rects = glyphRects(for: "a+b")
        XCTAssertGreaterThanOrEqual(rects.count, 3, "a+b should have at least 3 glyphs")
    }

    func testEquation() {
        let rects = glyphRects(for: "x=5")
        XCTAssertGreaterThanOrEqual(rects.count, 3)
    }

    // MARK: - Superscripts and subscripts

    func testSuperscript() {
        let rects = glyphRects(for: "x^2")
        XCTAssertGreaterThanOrEqual(rects.count, 2, "x^2 should have at least x and 2")
        // Find x and 2 rects
        let baseRects = rects.filter { $0.character.contains("𝑥") || $0.character.contains("x") }
        let supRects = rects.filter { $0.character == "2" }
        if let base = baseRects.first, let sup = supRects.first {
            // Superscript should be higher (smaller y in CoreText coords = higher up)
            XCTAssertGreaterThan(sup.rect.minY, base.rect.minY,
                                 "Superscript should be positioned above base")
        }
    }

    func testSubscript() {
        let rects = glyphRects(for: "a_1")
        XCTAssertGreaterThanOrEqual(rects.count, 2, "a_1 should have at least a and 1")
    }

    func testBothScripts() {
        let rects = glyphRects(for: "x_1^2")
        XCTAssertGreaterThanOrEqual(rects.count, 3, "x_1^2 should have at least 3 glyphs")
    }

    // MARK: - Fractions

    func testSimpleFraction() {
        let rects = glyphRects(for: "\\frac{a}{b}")
        // a, b, and the fraction line
        XCTAssertGreaterThanOrEqual(rects.count, 3, "Fraction should have numerator, denominator, and line")
        // Check fraction line exists
        let lines = rects.filter { $0.character == "—" }
        XCTAssertEqual(lines.count, 1, "Should have exactly one fraction line")
    }

    func testNestedFraction() {
        let rects = glyphRects(for: "\\frac{\\frac{a}{b}}{c}")
        // Inner fraction: a, b, line. Outer: inner + c + line
        XCTAssertGreaterThanOrEqual(rects.count, 5, "Nested fraction should have at least 5 elements")
    }

    func testFractionNumeratorAboveDenominator() {
        let rects = glyphRects(for: "\\frac{1}{2}")
        let ones = rects.filter { $0.character == "1" }
        let twos = rects.filter { $0.character == "2" }
        if let num = ones.first, let den = twos.first {
            // In CoreText coords (y-up), numerator y > denominator y
            XCTAssertGreaterThan(num.rect.minY, den.rect.minY,
                                 "Numerator should be above denominator")
        }
    }

    // MARK: - Square roots (radical)

    func testSquareRoot() {
        let rects = glyphRects(for: "\\sqrt{x}")
        XCTAssertGreaterThanOrEqual(rects.count, 2, "√x should have radical background + x")
        // First rect should be the radical background (√)
        let radicals = rects.filter { $0.character == "√" }
        XCTAssertEqual(radicals.count, 1, "Should have exactly one radical background rect")
    }

    func testSquareRootEnclosesContent() {
        let rects = glyphRects(for: "\\sqrt{x^2+y^2}")
        let radicals = rects.filter { $0.character == "√" }
        let innerRects = rects.filter { $0.character != "√" }
        XCTAssertEqual(radicals.count, 1, "Should have one radical rect")
        guard let radical = radicals.first else { return }
        // The radical rect should enclose all inner rects
        for inner in innerRects {
            XCTAssertTrue(radical.rect.contains(inner.rect) || radical.rect.intersects(inner.rect),
                          "Radical rect should enclose or intersect '\(inner.character)' at \(inner.rect)")
        }
    }

    func testSquareRootWithDegree() {
        let rects = glyphRects(for: "\\sqrt[3]{x}")
        XCTAssertGreaterThanOrEqual(rects.count, 3, "³√x should have radical + 3 + x")
    }

    // MARK: - Greek letters

    func testGreekLetters() {
        let rects = glyphRects(for: "\\alpha+\\beta")
        XCTAssertGreaterThanOrEqual(rects.count, 3, "α+β should have at least 3 glyphs")
        XCTAssertTrue(rects.allSatisfy { $0.rect.width > 0 && $0.rect.height > 0 })
    }

    // MARK: - Large operators with limits

    func testSummation() {
        let rects = glyphRects(for: "\\sum_{n=0}^{\\infty} a_n")
        XCTAssertGreaterThanOrEqual(rects.count, 5, "Summation with limits should have many glyphs")
        XCTAssertTrue(rects.allSatisfy { $0.rect.width > 0 && $0.rect.height > 0 })
    }

    func testIntegral() {
        let rects = glyphRects(for: "\\int_a^b f(x) dx")
        XCTAssertGreaterThanOrEqual(rects.count, 5, "Integral expression should have many glyphs")
    }

    func testProduct() {
        let rects = glyphRects(for: "\\prod_{i=1}^{n} x_i")
        XCTAssertGreaterThanOrEqual(rects.count, 5)
    }

    // MARK: - Delimiters

    func testParentheses() {
        let rects = glyphRects(for: "\\left(x\\right)")
        XCTAssertGreaterThanOrEqual(rects.count, 3, "(x) should have parens + x")
    }

    func testBrackets() {
        let rects = glyphRects(for: "\\left[a+b\\right]")
        XCTAssertGreaterThanOrEqual(rects.count, 4)
    }

    // MARK: - Matrices

    func testSimpleMatrix() {
        let rects = glyphRects(for: "\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}")
        XCTAssertGreaterThanOrEqual(rects.count, 4, "2x2 matrix should have at least 4 element glyphs")
    }

    // MARK: - Accents

    func testHatAccent() {
        let rects = glyphRects(for: "\\hat{x}")
        XCTAssertGreaterThanOrEqual(rects.count, 2, "x̂ should have x and accent")
    }

    func testVectorAccent() {
        let rects = glyphRects(for: "\\vec{v}")
        XCTAssertGreaterThanOrEqual(rects.count, 2, "v⃗ should have v and accent")
    }

    func testBarAccent() {
        let rects = glyphRects(for: "\\bar{x}")
        XCTAssertGreaterThanOrEqual(rects.count, 2)
    }

    // MARK: - Overline / underline

    func testOverline() {
        let rects = glyphRects(for: "\\overline{AB}")
        XCTAssertGreaterThanOrEqual(rects.count, 2, "Overline should have A, B and possibly line")
    }

    // MARK: - Complex expressions

    func testEulersIdentity() {
        let rects = glyphRects(for: "e^{i\\pi}+1=0")
        XCTAssertGreaterThanOrEqual(rects.count, 6)
        XCTAssertTrue(rects.allSatisfy { $0.rect.width > 0 && $0.rect.height > 0 },
                      "All glyphs should have positive dimensions")
    }

    func testQuadraticFormula() {
        let rects = glyphRects(for: "x=\\frac{-b\\pm\\sqrt{b^2-4ac}}{2a}")
        XCTAssertGreaterThanOrEqual(rects.count, 10, "Quadratic formula should have many glyphs")
        // Should have both fraction line and radical
        let fractionLines = rects.filter { $0.character == "—" }
        let radicals = rects.filter { $0.character == "√" }
        XCTAssertGreaterThanOrEqual(fractionLines.count, 1, "Should have a fraction line")
        XCTAssertEqual(radicals.count, 1, "Should have one radical")
    }

    func testLimitExpression() {
        let rects = glyphRects(for: "\\lim_{x \\to 0} \\frac{\\sin x}{x}")
        XCTAssertGreaterThanOrEqual(rects.count, 5)
    }

    func testTrigExpression() {
        let rects = glyphRects(for: "\\sin^2\\theta + \\cos^2\\theta = 1")
        XCTAssertGreaterThanOrEqual(rects.count, 8)
    }

    // MARK: - No overlap of sibling rects

    func testNoOverlapSimple() {
        let rects = glyphRects(for: "a+b=c")
        // Adjacent glyphs at the same level should not overlap horizontally
        let sorted = rects.sorted { $0.rect.minX < $1.rect.minX }
        for i in 1..<sorted.count {
            let prev = sorted[i-1].rect
            let curr = sorted[i].rect
            // Allow small overlap (< 2px) due to font metrics
            XCTAssertLessThan(prev.maxX - curr.minX, 2,
                              "'\(sorted[i-1].character)' and '\(sorted[i].character)' overlap too much")
        }
    }

    // MARK: - All rects have valid dimensions

    func testAllRectsPositiveDimensions() {
        let expressions = [
            "x", "x^2", "\\frac{1}{2}", "\\sqrt{2}", "\\sum_{i=0}^{n} i",
            "\\alpha\\beta\\gamma", "\\int_0^1 x dx", "a+b=c",
        ]
        for expr in expressions {
            let rects = glyphRects(for: expr)
            XCTAssertGreaterThan(rects.count, 0, "'\(expr)' should produce glyphs")
            for glyph in rects {
                XCTAssertGreaterThan(glyph.rect.width, 0,
                                     "'\(expr)' glyph '\(glyph.character)' has zero width")
                XCTAssertGreaterThan(glyph.rect.height, 0,
                                     "'\(expr)' glyph '\(glyph.character)' has zero height")
            }
        }
    }

    // MARK: - Empty / invalid input

    func testEmptyLatex() {
        let rects = glyphRects(for: "")
        XCTAssertEqual(rects.count, 0)
    }

    func testSpaceOnly() {
        let rects = glyphRects(for: " ")
        // Space may or may not produce glyphs, but should not crash
        XCTAssertTrue(true)
    }
}
