from sympy import simplify, factor
from autocomplete.document_line_parser import ParsedExpression


def simplify_expression(line: ParsedExpression) -> str:
    return str(simplify(line.expression))


def factor_expression(line: ParsedExpression) -> str:
    return str(factor(line.expression))
