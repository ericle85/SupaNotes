#!/usr/bin/env python3
"""Render LaTeX test cases using matplotlib for visual comparison with our custom renderer."""
import os
import matplotlib
matplotlib.use('Agg')
matplotlib.rcParams['text.usetex'] = True
matplotlib.rcParams['text.latex.preamble'] = r'\usepackage{amsmath,amssymb}'
import matplotlib.pyplot as plt

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "output_latex")
os.makedirs(OUTPUT_DIR, exist_ok=True)

# Same test cases as render_test_cases.swift
CASES = {
    # Basic
    "simple_number": r"$= 6$",
    "simple_expression": r"$x + 3 = 7$",
    "multiplication": r"$2 \times 3 = 6$",
    "negative": r"$-5 + 3 = -2$",
    # Fractions
    "fraction_simple": r"$\frac{1}{2}$",
    "fraction_in_expr": r"$x = \frac{a + b}{c}$",
    "fraction_nested": r"$\frac{\frac{1}{2}}{3}$",
    "fraction_derivative": r"$\frac{dy}{dx}$",
    # Scripts
    "superscript": r"$x^{2}$",
    "subscript": r"$a_{n}$",
    "both_scripts": r"$x_{i}^{2}$",
    "euler_exponent": r"$e^{i \pi}$",
    # Summation & Products
    "summation": r"$\sum_{n=0}^{\infty} a_{n}$",
    "product": r"$\prod_{i=1}^{n} x_{i}$",
    "summation_fraction": r"$\sum_{n=1}^{\infty} \frac{1}{n^{2}}$",
    # Integrals
    "integral": r"$\int_{0}^{1} x^{2} dx$",
    "integral_fraction": r"$\int \frac{1}{x} dx$",
    "gaussian_integral": r"$\int_{-\infty}^{\infty} e^{-x^{2}} dx = \sqrt{\pi}$",
    "double_integral": r"$\int \int_{D} f(x, y) dA$",
    "integral_matrix": r"$\int_{0}^{1} \begin{pmatrix} t \\ t^{2} \end{pmatrix} dt$",
    # Limits
    "limit": r"$\lim_{x \to 0} \frac{\sin x}{x}$",
    # Square Roots
    "sqrt_simple": r"$\sqrt{x}$",
    "sqrt_expression": r"$\sqrt{a^{2} + b^{2}}$",
    "sqrt_fraction": r"$\sqrt{\frac{1}{2}}$",
    # Matrices
    "matrix_2x1": r"$\begin{pmatrix} 4 \\ 2 \end{pmatrix}$",
    "matrix_2x2": r"$\begin{pmatrix} a & b \\ c & d \end{pmatrix}$",
    "matrix_bracket": r"$\begin{bmatrix} 1 & 0 \\ 0 & 1 \end{bmatrix}$",
    "matrix_with_var": r"$A = \begin{pmatrix} 1 & 2 \\ 3 & 4 \end{pmatrix}$",
    "determinant": r"$\det \begin{pmatrix} a & b \\ c & d \end{pmatrix} = ad - bc$",
    "nullspace": r"$N(A) = \left\{ \vec{x} \in \mathbb{R}^{n} : A\vec{x} = \vec{0} \right\}$",
    "system_of_equations": r"$\begin{cases} 2x + 3y = 7 \\ x - y = 1 \end{cases}$",
    "system_3_equations": r"$\begin{cases} x + y + z = 6 \\ 2x - y = 1 \\ x + z = 4 \end{cases}$",
    "span": r"$\operatorname{span} \left\{ \vec{v}_{1}, \vec{v}_{2} \right\}$",
    # Greek
    "greek_letters": r"$\alpha + \beta = \gamma$",
    "greek_delta": r"$\Delta x = x_{1} - x_{0}$",
    # Accents
    "accent_vec": r"$\vec{v}$",
    "accent_hat": r"$\hat{x}$",
    "accent_bar": r"$\bar{x}$",
    "accent_overline": r"$\overline{AB}$",
    "accent_dot": r"$\dot{x}$",
    "accent_tilde": r"$\tilde{x}$",
    # Delimiters
    "delimited_parens": r"$\left( x + 1 \right)$",
    "delimited_brackets": r"$\left[ a, b \right]$",
    # Complex
    "quadratic_formula": r"$x = \frac{-b \pm \sqrt{b^{2} - 4ac}}{2a}$",
    "taylor_series": r"$\sum_{n=0}^{\infty} \frac{f^{(n)}(a)}{n!} (x - a)^{n}$",
    "euler_identity": r"$e^{i\pi} + 1 = 0$",
    "pythagorean": r"$a^{2} + b^{2} = c^{2}$",
}

def render_case(name: str, latex: str):
    fig, ax = plt.subplots(figsize=(6, 2))
    ax.text(0.5, 0.5, latex, fontsize=28, ha='center', va='center',
            transform=ax.transAxes)
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis('off')
    fig.patch.set_facecolor('white')
    path = os.path.join(OUTPUT_DIR, f"{name}.png")
    fig.savefig(path, dpi=150, bbox_inches='tight', pad_inches=0.1,
                facecolor='white', edgecolor='none')
    plt.close(fig)

if __name__ == "__main__":
    for name, latex in CASES.items():
        render_case(name, latex)
        print(f"  {name}.png")
    print(f"\n{len(CASES)} reference images → {OUTPUT_DIR}/")
