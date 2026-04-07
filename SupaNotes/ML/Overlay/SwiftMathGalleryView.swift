import SwiftUI
import SwiftMath

/// Visual gallery of SwiftMath renders with/without bounding boxes for manual inspection.
struct SwiftMathGalleryView: View {
    @State private var showBoxes = true
    @State private var fontSize: Double = 36
    @State private var searchText = ""

    private let renderer = SwiftMathRenderer()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Toggle("Boxes", isOn: $showBoxes).fixedSize()
                Spacer()
                Text("Size: \(Int(fontSize))pt").font(.caption.monospaced())
                Slider(value: $fontSize, in: 20...64, step: 4).frame(width: 200)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            TextField("Filter…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredCases, id: \.0) { label, latex in
                        GalleryRow(label: label, latex: latex, fontSize: CGFloat(fontSize),
                                   showBoxes: showBoxes, renderer: renderer)
                        Divider()
                    }
                }
            }
        }
        .navigationTitle("SwiftMath Gallery")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var filteredCases: [(String, String)] {
        if searchText.isEmpty { return Self.testCases }
        let q = searchText.lowercased()
        return Self.testCases.filter { $0.0.lowercased().contains(q) || $0.1.lowercased().contains(q) }
    }

    // MARK: - Test cases

    static let testCases: [(String, String)] = [
        // Simple variables and numbers
        ("Simple x", "x"),
        ("Simple y", "y"),
        ("Number 123", "123"),
        ("Multi-letter", "abc"),
        ("Decimal", "3.14"),
        ("Negative number", "-42"),

        // Basic operations
        ("Addition", "a + b"),
        ("Subtraction", "a - b"),
        ("Multiplication dot", "a \\cdot b"),
        ("Multiplication times", "a \\times b"),
        ("Division", "a \\div b"),
        ("Equality", "a = b"),
        ("Inequality", "a \\neq b"),
        ("Less than", "a < b"),
        ("Greater equal", "a \\geq b"),

        // Fractions
        ("Simple fraction", "\\frac{1}{2}"),
        ("Variable fraction", "\\frac{x}{y}"),
        ("Nested frac numer", "\\frac{\\frac{1}{2}}{3}"),
        ("Nested frac denom", "\\frac{1}{\\frac{2}{3}}"),
        ("Complex fraction", "\\frac{x^2 + 2x + 1}{x - 1}"),
        ("Double nested frac", "\\frac{\\frac{a}{b}}{\\frac{c}{d}}"),

        // Square roots
        ("Simple sqrt", "\\sqrt{2}"),
        ("Sqrt expression", "\\sqrt{x^2 + y^2}"),
        ("Cube root", "\\sqrt[3]{8}"),
        ("Nth root", "\\sqrt[n]{x}"),
        ("Nested sqrt", "\\sqrt{\\sqrt{x}}"),
        ("Sqrt in fraction", "\\frac{1}{\\sqrt{2}}"),

        // Superscripts and subscripts
        ("Superscript", "x^2"),
        ("Subscript", "x_i"),
        ("Both scripts", "x_i^2"),
        ("Nested superscript", "x^{y^2}"),
        ("Multi-char sub", "x_{ij}"),
        ("Both multi", "a_{mn}^{pq}"),

        // Greek letters
        ("Alpha beta", "\\alpha + \\beta"),
        ("Pi", "\\pi"),
        ("Sigma", "\\Sigma"),
        ("Omega", "\\omega"),
        ("Lambda mu", "\\lambda \\mu"),
        ("Delta epsilon", "\\Delta \\epsilon"),
        ("Phi psi", "\\phi + \\psi"),
        ("Theta", "\\theta"),

        // Summations
        ("Simple sum", "\\sum_{i=1}^{n} i"),
        ("Sum expression", "\\sum_{k=0}^{\\infty} x^k"),
        ("Sum fraction", "\\sum_{i=1}^{n} \\frac{1}{i}"),

        // Integrals
        ("Indefinite integral", "\\int x^2 \\, dx"),
        ("Definite integral", "\\int_0^1 x^2 \\, dx"),
        ("Integral infinity", "\\int_{-\\infty}^{\\infty} e^{-x^2} \\, dx"),
        ("Double integral", "\\iint_D f(x,y) \\, dA"),

        // Products and limits
        ("Product", "\\prod_{i=1}^{n} x_i"),
        ("Simple limit", "\\lim_{x \\to 0} \\frac{\\sin x}{x}"),
        ("Limit infinity", "\\lim_{n \\to \\infty} \\left(1 + \\frac{1}{n}\\right)^n"),

        // Matrices
        ("2x2 matrix", "\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}"),
        ("3x3 identity", "\\begin{pmatrix} 1 & 0 & 0 \\\\ 0 & 1 & 0 \\\\ 0 & 0 & 1 \\end{pmatrix}"),
        ("Column vector", "\\begin{bmatrix} x \\\\ y \\\\ z \\end{bmatrix}"),
        ("Determinant", "\\begin{vmatrix} a & b \\\\ c & d \\end{vmatrix}"),

        // Trig functions
        ("Sine", "\\sin(x)"),
        ("Cosine squared", "\\cos^2(\\theta)"),
        ("Trig identity", "\\sin^2 x + \\cos^2 x = 1"),
        ("Tangent", "\\tan\\left(\\frac{\\pi}{4}\\right)"),

        // Logarithms
        ("Natural log", "\\ln(x)"),
        ("Log base 10", "\\log_{10}(x)"),
        ("Log base n", "\\log_n x"),

        // Accents
        ("Hat accent", "\\hat{x}"),
        ("Vec accent", "\\vec{v}"),
        ("Bar accent", "\\bar{x}"),
        ("Dot accent", "\\dot{x}"),
        ("Tilde accent", "\\tilde{f}"),
        ("Double dot", "\\ddot{x}"),

        // Overline/underline
        ("Overline", "\\overline{AB}"),
        ("Underline", "\\underline{x + y}"),

        // Delimiters
        ("Auto parens", "\\left( \\frac{x}{y} \\right)"),
        ("Auto brackets", "\\left[ \\frac{a}{b} \\right]"),
        ("Auto braces", "\\left\\{ x \\in \\mathbb{R} \\right\\}"),
        ("Mixed delimiters", "\\left( \\frac{1}{1 + \\frac{1}{x}} \\right)"),

        // Binomial coefficients
        ("Binomial n k", "\\binom{n}{k}"),
        ("Binomial expr", "\\binom{n}{k} p^k (1-p)^{n-k}"),

        // Famous equations
        ("Euler identity", "e^{i\\pi} + 1 = 0"),
        ("Pythagorean", "a^2 + b^2 = c^2"),
        ("Quadratic formula", "x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}"),
        ("Einstein", "E = mc^2"),
        ("Gaussian", "f(x) = \\frac{1}{\\sigma\\sqrt{2\\pi}} e^{-\\frac{(x-\\mu)^2}{2\\sigma^2}}"),

        // Multi-operator
        ("Polynomial", "3x^3 - 2x^2 + x - 7"),
        ("Mixed ops", "\\frac{a+b}{c} \\cdot \\sqrt{d} + e^f"),

        // Deeply nested
        ("Frac sqrt frac", "\\frac{1}{\\sqrt{\\frac{x+1}{x-1}}}"),
        ("Triple nested sqrt", "\\sqrt{1 + \\sqrt{1 + \\sqrt{x}}}"),
        ("Deep fraction", "\\frac{\\frac{x^2}{y}}{\\frac{a}{\\sqrt{b}}}"),

        // Text mixed
        ("Text in math", "x \\text{ if } x > 0"),

        // Calculus
        ("Derivative", "\\frac{dy}{dx}"),
        ("Second derivative", "\\frac{d^2y}{dx^2}"),
        ("Partial derivative", "\\frac{\\partial f}{\\partial x}"),
        ("Chain rule", "\\frac{dy}{dx} = \\frac{dy}{du} \\cdot \\frac{du}{dx}"),

        // Set notation
        ("Set membership", "x \\in A"),
        ("Subset", "A \\subseteq B"),
        ("Union intersect", "A \\cup B \\cap C"),
        ("Set builder", "\\{ x \\mid x > 0 \\}"),

        // Absolute values and floor/ceiling
        ("Absolute value", "\\left| x \\right|"),
        ("Abs expression", "\\left| \\frac{x+1}{x-1} \\right|"),
        ("Floor", "\\lfloor x \\rfloor"),
        ("Ceiling", "\\lceil x \\rceil"),
        ("Floor fraction", "\\left\\lfloor \\frac{n}{2} \\right\\rfloor"),

        // Extra edge cases
        ("Empty group", "{}"),
        ("Single paren", "(x)"),
        ("Ellipsis", "a_1, a_2, \\ldots, a_n"),
        ("Infinity", "\\infty"),
        ("Plus minus", "\\pm"),
        ("Arrow", "A \\rightarrow B"),
        ("Mapsto", "f: X \\mapsto Y"),
        ("Nabla", "\\nabla f"),
        ("Tensor product", "A \\otimes B"),
    ]
}

// MARK: - Gallery Row

private struct GalleryRow: View {
    let label: String
    let latex: String
    let fontSize: CGFloat
    let showBoxes: Bool
    let renderer: SwiftMathRenderer

    @State private var plainImage: UIImage?
    @State private var debugImage: UIImage?
    @State private var glyphCount: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption.bold())
                Spacer()
                Text("\(glyphCount) glyphs").font(.caption2.monospaced()).foregroundStyle(.secondary)
            }
            Text(latex).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)

            HStack(spacing: 12) {
                // Plain render
                Group {
                    if let img = plainImage {
                        Image(uiImage: img).resizable().scaledToFit()
                    } else {
                        Text("⚠️").frame(maxWidth: .infinity)
                    }
                }
                .frame(maxHeight: 120)
                .background(Color.white)
                .cornerRadius(6)

                // Debug render (with boxes)
                if showBoxes {
                    Group {
                        if let img = debugImage {
                            Image(uiImage: img).resizable().scaledToFit()
                        } else {
                            Text("⚠️").frame(maxWidth: .infinity)
                        }
                    }
                    .frame(maxHeight: 120)
                    .background(Color.white)
                    .cornerRadius(6)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .onAppear { render() }
        .onChange(of: fontSize) { render() }
        .onChange(of: showBoxes) { render() }
    }

    private func render() {
        let plain = renderer.render(latex: latex, fontSize: fontSize)
        plainImage = plain?.image
        glyphCount = plain?.glyphRects.count ?? 0

        if showBoxes {
            debugImage = renderer.renderWithDebug(latex: latex, fontSize: fontSize)?.image
        }
    }
}

#Preview {
    NavigationStack {
        SwiftMathGalleryView()
    }
}
