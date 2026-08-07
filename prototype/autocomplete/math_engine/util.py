from sympy import Rational, fraction, gcd


def is_unsimplified_fraction(expression) -> bool:
    numerator, denominator = fraction(expression)
    if denominator == 1:
        return False
    return gcd(numerator, denominator) != 1


def format_result(original_expression, simplified_result) -> str:
    if is_unsimplified_fraction(original_expression):
        return str(simplified_result)

    if isinstance(simplified_result, Rational) and not simplified_result.is_integer:
        return str(round(float(simplified_result), 3))

    return str(simplified_result)
