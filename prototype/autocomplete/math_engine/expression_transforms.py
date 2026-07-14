from sympy import simplify, factor, expand, cancel
from autocomplete.document_line_parser import ParsedExpression, ParsedEquation


def simplify_expression(line: ParsedExpression) -> str:
    expr = line.expression
    # For Add expressions with powers, prefer expand over simplify
    # to avoid unwanted factoring (x**2 + 5*x should stay as-is, not become x*(x + 5))
    if expr.is_Add and any(arg.is_Pow for arg in expr.args):
        expanded = expand(expr)
        if expanded != expr:
            return str(expanded)
        # If expand didn't change anything, return as-is (don't fall through to simplify)
        return str(expr)
    simplified = simplify(expr)
    if simplified != expr:
        return str(simplified)
    return str(expr)


def factor_expression(line: ParsedExpression) -> str:
    return str(factor(line.expression))


def expand_expression(line: ParsedExpression) -> str:
    return str(expand(line.expression))


def cancel_expression(line: ParsedExpression) -> str:
    return str(cancel(line.expression))


def simplify_equation(line: ParsedEquation) -> str:
    """Simplify both sides of an equation."""
    left = str(simplify(line.left_side))
    right = str(simplify(line.right_side))
    return f'{left} = {right}'


def factor_equation(line: ParsedEquation) -> str:
    """Factor both sides of an equation."""
    left = str(factor(line.left_side))
    right = str(factor(line.right_side))
    return f'{left} = {right}'


def expand_equation(line: ParsedEquation) -> str:
    """Expand both sides of an equation."""
    left = str(expand(line.left_side))
    right = str(expand(line.right_side))
    return f'{left} = {right}'


def cancel_equation(line: ParsedEquation) -> str:
    """Cancel both sides of an equation."""
    left = str(cancel(line.left_side))
    right = str(cancel(line.right_side))
    return f'{left} = {right}'
