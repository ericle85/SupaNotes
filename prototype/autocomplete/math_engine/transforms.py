from sympy import symbols, laplace_transform, inverse_laplace_transform, fourier_transform
from autocomplete.document_line_parser import ParsedExpression


time_variable = symbols("t")
laplace_variable = symbols("s")
fourier_variable = symbols("w")


def compute_laplace_transform(line: ParsedExpression) -> str:
    transformed_expression = laplace_transform(
        line.expression, time_variable, laplace_variable, noconds=True
    )
    return str(transformed_expression)


def compute_inverse_laplace_transform(line: ParsedExpression) -> str:
    original_time_expression = inverse_laplace_transform(
        line.expression, laplace_variable, time_variable
    )
    return str(original_time_expression)


def compute_fourier_transform(line: ParsedExpression) -> str:
    transformed_expression = fourier_transform(
        line.expression, time_variable, fourier_variable
    )
    return str(transformed_expression)
