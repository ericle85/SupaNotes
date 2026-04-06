#!/usr/bin/env python3
"""Render LaTeX test cases using pdflatex + sips for authentic Computer Modern output."""
import os
import subprocess
import tempfile
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
OUTPUT_DIR = SCRIPT_DIR / "output_latex"

# Same test cases as render_test_cases.swift
CASES = {
    # Basic
    "simple_number": r"= 6",
    "simple_expression": r"x + 3 = 7",
    "multiplication": r"2 \times 3 = 6",
    "negative": r"-5 + 3 = -2",
    # Fractions
    "fraction_simple": r"\frac{1}{2}",
    "fraction_in_expr": r"x = \frac{a + b}{c}",
    "fraction_nested": r"\frac{\frac{1}{2}}{3}",
    "fraction_derivative": r"\frac{dy}{dx}",
    # Scripts
    "superscript": r"x^{2}",
    "subscript": r"a_{n}",
    "both_scripts": r"x_{i}^{2}",
    "euler_exponent": r"e^{i \pi}",
    # Summation & Products
    "summation": r"\sum_{n=0}^{\infty} a_{n}",
    "product": r"\prod_{i=1}^{n} x_{i}",
    "summation_fraction": r"\sum_{n=1}^{\infty} \frac{1}{n^{2}}",
    # Integrals
    "integral": r"\int_{0}^{1} x^{2} dx",
    "integral_fraction": r"\int \frac{1}{x} dx",
    "gaussian_integral": r"\int_{-\infty}^{\infty} e^{-x^{2}} dx = \sqrt{\pi}",
    "double_integral": r"\int \int_{D} f(x, y) dA",
    "integral_matrix": r"\int_{0}^{1} \begin{pmatrix} t \\ t^{2} \end{pmatrix} dt",
    # Limits
    "limit": r"\lim_{x \to 0} \frac{\sin x}{x}",
    # Square Roots
    "sqrt_simple": r"\sqrt{x}",
    "sqrt_expression": r"\sqrt{a^{2} + b^{2}}",
    "sqrt_fraction": r"\sqrt{\frac{1}{2}}",
    # Matrices
    "matrix_2x1": r"\begin{pmatrix} 4 \\ 2 \end{pmatrix}",
    "matrix_2x2": r"\begin{pmatrix} a & b \\ c & d \end{pmatrix}",
    "matrix_bracket": r"\begin{bmatrix} 1 & 0 \\ 0 & 1 \end{bmatrix}",
    "matrix_with_var": r"A = \begin{pmatrix} 1 & 2 \\ 3 & 4 \end{pmatrix}",
    "determinant": r"\det \begin{pmatrix} a & b \\ c & d \end{pmatrix} = ad - bc",
    "nullspace": r"N(A) = \left\{ \vec{x} \in \mathbb{R}^{n} : A\vec{x} = \vec{0} \right\}",
    "system_of_equations": r"\begin{cases} 2x + 3y = 7 \\ x - y = 1 \end{cases}",
    "system_3_equations": r"\begin{cases} x + y + z = 6 \\ 2x - y = 1 \\ x + z = 4 \end{cases}",
    "span": r"\operatorname{span} \left\{ \vec{v}_{1}, \vec{v}_{2} \right\}",
    # Greek
    "greek_letters": r"\alpha + \beta = \gamma",
    "greek_delta": r"\Delta x = x_{1} - x_{0}",
    # Accents
    "accent_vec": r"\vec{v}",
    "accent_hat": r"\hat{x}",
    "accent_bar": r"\bar{x}",
    "accent_overline": r"\overline{AB}",
    "accent_dot": r"\dot{x}",
    "accent_tilde": r"\tilde{x}",
    # Delimiters
    "delimited_parens": r"\left( x + 1 \right)",
    "delimited_brackets": r"\left[ a, b \right]",
    # Complex
    "quadratic_formula": r"x = \frac{-b \pm \sqrt{b^{2} - 4ac}}{2a}",
    "taylor_series": r"\sum_{n=0}^{\infty} \frac{f^{(n)}(a)}{n!} (x - a)^{n}",
    "euler_identity": r"e^{i\pi} + 1 = 0",
    "pythagorean": r"a^{2} + b^{2} = c^{2}",
    # Mixed text+math
    "mixed_text_math": r"\text{Area} = \pi r^{2}",
    "mixed_sentence": r"\text{If } x > 0 \text{, then } f(x) = x^{2}",
    "chained_exponent": r"2^{2^{2}}",
}

LATEX_TEMPLATE = r"""\documentclass[border=2pt]{{standalone}}
\usepackage{{amsmath,amssymb}}
\begin{{document}}
$\displaystyle {formula}$
\end{{document}}
"""


def render_case(name: str, formula: str) -> bool:
    """Render a single LaTeX formula to PNG. Returns True on success."""
    OUTPUT_DIR.mkdir(exist_ok=True)
    out_png = OUTPUT_DIR / f"{name}.png"

    with tempfile.TemporaryDirectory() as tmpdir:
        tex_path = os.path.join(tmpdir, "formula.tex")
        pdf_path = os.path.join(tmpdir, "formula.pdf")

        with open(tex_path, "w") as f:
            f.write(LATEX_TEMPLATE.format(formula=formula))

        # Run pdflatex
        result = subprocess.run(
            ["pdflatex", "-interaction=nonstopmode", "-output-directory", tmpdir, tex_path],
            capture_output=True, text=True, timeout=15,
        )
        if result.returncode != 0 or not os.path.exists(pdf_path):
            print(f"  FAIL {name}: pdflatex error")
            return False

        # Convert PDF to PNG using pdftoppm (poppler) at high DPI
        png_prefix = os.path.join(tmpdir, "out")
        subprocess.run(
            ["pdftoppm", "-png", "-r", "600", pdf_path, png_prefix],
            capture_output=True, timeout=10,
        )
        # pdftoppm outputs out-1.png
        tmp_png = os.path.join(tmpdir, "out-1.png")
        if not os.path.exists(tmp_png):
            print(f"  FAIL {name}: pdftoppm conversion failed")
            return False
        import shutil
        shutil.move(tmp_png, str(out_png))

    return True


def main() -> None:
    ok = 0
    fail = 0
    for name, formula in CASES.items():
        if render_case(name, formula):
            print(f"  {name}.png")
            ok += 1
        else:
            fail += 1

    print(f"\n{ok} reference images → {OUTPUT_DIR}/")
    if fail:
        print(f"{fail} failures")


if __name__ == "__main__":
    main()
