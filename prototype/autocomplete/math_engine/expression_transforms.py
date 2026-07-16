from sympy import simplify, factor, expand, cancel, N
from autocomplete.document_line_parser import ParsedExpression, ParsedEquation
from autocomplete.math_engine.latex_format import to_latex


def simplify_expression(line: ParsedExpression) -> str:
    expr = line.expression
    # For Add expressions with powers, prefer expand over simplify
    # to avoid unwanted factoring (x**2 + 5*x should stay as-is, not become x*(x + 5))
    if expr.is_Add and any(arg.is_Pow for arg in expr.args):
        expanded = expand(expr)
        if expanded != expr:
            return to_latex(expanded)
        # If expand didn't change anything, return as-is (don't fall through to simplify)
        return to_latex(expr)
    simplified = simplify(expr)
    if simplified != expr:
        return to_latex(simplified)
    return to_latex(expr)


def convert_expression_to_decimal(line: ParsedExpression) -> str:
    return to_latex(N(line.expression))


def suggest_undefined_result(line: ParsedExpression) -> str:
    return "undefined"


def factor_expression(line: ParsedExpression) -> str:
    return to_latex(factor(line.expression))


def expand_expression(line: ParsedExpression) -> str:
    return to_latex(expand(line.expression))


def cancel_expression(line: ParsedExpression) -> str:
    return to_latex(cancel(line.expression))


def simplify_equation(line: ParsedEquation) -> str:
    """Simplify both sides of an equation."""
    left = to_latex(simplify(line.left_side))
    right = to_latex(simplify(line.right_side))
    return f'{left} = {right}'


def factor_equation(line: ParsedEquation) -> str:
    """Factor both sides of an equation."""
    left = to_latex(factor(line.left_side))
    right = to_latex(factor(line.right_side))
    return f'{left} = {right}'


def expand_equation(line: ParsedEquation) -> str:
    """Expand both sides of an equation."""
    left = to_latex(expand(line.left_side))
    right = to_latex(expand(line.right_side))
    return f'{left} = {right}'


def cancel_equation(line: ParsedEquation) -> str:
    """Cancel both sides of an equation."""
    left = to_latex(cancel(line.left_side))
    right = to_latex(cancel(line.right_side))
    return f'{left} = {right}'
