"""LaTeX formatter for math engine output.

Converts sympy expressions back to LaTeX format for display.
Optional: used when user prefers LaTeX output over plain text.
"""

import re
import sympy
from sympy import Symbol, S, sin, cos, tan, exp, log, sqrt, I, pi, oo, Pow
from sympy.printing.latex import latex


def format_to_latex(expr) -> str:
    """Convert a sympy expression to LaTeX string.

    Args:
        expr: sympy expression or string

    Returns:
        LaTeX-formatted string
    """
    if isinstance(expr, str):
        try:
            expr = sympy.sympify(expr)
        except Exception:
            return expr

    result = latex(expr)
    return result


def format_expression(expr, latex_output: bool = False) -> str:
    """Format an expression for output.

    Args:
        expr: sympy expression or string
        latex_output: if True, output LaTeX; otherwise plain text

    Returns:
        Formatted string
    """
    if not latex_output:
        if isinstance(expr, str):
            return expr
        return str(sympy.simplify(expr))

    return format_to_latex(expr)


def format_equation(left, right, latex_output: bool = False) -> str:
    """Format an equation for output.

    Args:
        left: left side of equation
        right: right side of equation
        latex_output: if True, output LaTeX; otherwise plain text

    Returns:
        Formatted equation string
    """
    if latex_output:
        left_latex = format_to_latex(left)
        right_latex = format_to_latex(right)
        return f'{left_latex} = {right_latex}'
    return f'{left} = {right}'
