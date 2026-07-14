from sympy import Symbol, diff, integrate, limit, series, sympify
from autocomplete.document_line_parser import ParsedExpression


def differentiate_expression(line: ParsedExpression, variable_name: str) -> str:
    variable = Symbol(variable_name)
    return str(diff(line.expression, variable))


def integrate_expression(line: ParsedExpression, variable_name: str) -> str:
    variable = Symbol(variable_name)
    return str(integrate(line.expression, variable))


def compute_limit_at_point(
    line: ParsedExpression, variable_name: str, approached_value: str
) -> str:
    variable = Symbol(variable_name)
    approached_point = sympify(approached_value)
    return str(limit(line.expression, variable, approached_point))


def expand_as_taylor_series(
    line: ParsedExpression,
    variable_name: str,
    expansion_point: str = "0",
    number_of_terms: int = 6,
) -> str:
    variable = Symbol(variable_name)
    truncated_series = series(
        line.expression, variable, sympify(expansion_point), number_of_terms
    ).removeO()
    return str(truncated_series)
