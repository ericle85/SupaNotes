from dataclasses import dataclass
from typing import Callable
from sympy import Add, Pow, sin, cos, tan, exp, log, factorint, gcd, I, N, S
from sympy.core.alphabets import greeks

from autocomplete.document_context_model import DocumentContext
from autocomplete.document_line_parser import ParsedEquation, ParsedExpression, UnparsableLine
from autocomplete.math_engine import (
    equation_solving,
    expression_transforms,
    calculus,
    complex_numbers,
)


@dataclass(frozen=True)
class GhostText:
    text: str
    placement: str


@dataclass(frozen=True)
class SuggestedNextLine:
    suggested_text: str
    operation: str
    diagnostic_reason: str = ""
    ghost_text: GhostText | None = None

    @property
    def has_suggestion(self) -> bool:
        return self.diagnostic_reason == ""


def generate_next_line(context: DocumentContext) -> SuggestedNextLine:
    line = context.current_line
    if isinstance(line, UnparsableLine):
        return SuggestedNextLine("", "simplify_expression", line.parse_error_description)
    evaluated = _try_evaluate_numeric(line, context.preceding_lines)
    if evaluated is not None:
        return evaluated
    if isinstance(line, ParsedEquation):
        return _execute_equation(line, _resolve_equation(line))
    return _execute_expression(line, _resolve_expression(line))


def _definitions_from_preceding(preceding_lines) -> dict:
    return {
        line.left_side: line.right_side
        for line in preceding_lines
        if isinstance(line, ParsedEquation)
        and line.left_side.is_Symbol
        and not line.right_side.free_symbols
    }


def _calculator_result_text(numeric) -> str:
    value = float(numeric)
    if value.is_integer():
        return str(int(value))
    return str(round(value, 2))


def _numeric_equals_placement(line):
    if not isinstance(line, ParsedExpression):
        return None
    if line.has_trailing_equals:
        return "right"
    if line.has_leading_equals:
        return "left"
    return None


def _try_evaluate_numeric(line, preceding_lines):
    placement = _numeric_equals_placement(line)
    if placement is None:
        return None
    resolved = line.expression.subs(_definitions_from_preceding(preceding_lines))
    numeric = N(resolved)
    if numeric.is_number and numeric.is_real is False:
        return None
    if resolved.free_symbols or not numeric.is_number:
        return SuggestedNextLine("", "evaluate_numeric", "expression has unknown or non-numeric terms")
    result_text = _calculator_result_text(numeric)
    return SuggestedNextLine(
        result_text,
        "evaluate_numeric",
        ghost_text=GhostText(result_text, placement),
    )


def _resolve_equation(line: ParsedEquation) -> str:
    for matches, operation in _equation_rules:
        if matches(line):
            return operation
    return "solve_equation_one_step"


def _resolve_expression(line: ParsedExpression) -> str:
    for matches, operation in _expression_rules:
        if matches(line):
            return operation
    return "simplify_expression"


def _either_side(predicate: Callable) -> Callable[[ParsedEquation], bool]:
    return lambda line: predicate(line.left_side) or predicate(line.right_side)


def _contains_trig(expr) -> bool:
    return expr.has(sin, cos, tan)


def _contains_exp(expr) -> bool:
    return expr.has(exp)


def _contains_log(expr) -> bool:
    return expr.has(log)


def _contains_sqrt(expr) -> bool:
    return any(power.exp == S.Half for power in expr.atoms(Pow))


_GREEK_NAMES = frozenset(greeks)


def _is_manipulable_variable(name: str) -> bool:
    if len(name) == 1 and name.isalpha():
        return True
    return name.lower().removeprefix("var") in _GREEK_NAMES


def _has_single_unknown(line: ParsedEquation) -> bool:
    names = {symbol.name for symbol in line.left_side.free_symbols | line.right_side.free_symbols}
    if len(names) <= 1:
        return True
    return all(_is_manipulable_variable(name) for name in names) or "x" in names


def _is_factor_form_equation(line: ParsedEquation) -> bool:
    if line.right_side != 0 or not line.left_side.is_Mul:
        return False
    binomial_factors = [
        factor for factor in line.left_side.args
        if factor.is_Add or (factor.is_Mul and len(factor.free_symbols) > 0)
    ]
    return len(binomial_factors) >= 2


def _is_quadratic_equation(line: ParsedEquation) -> bool:
    for symbol in line.left_side.free_symbols | line.right_side.free_symbols:
        polynomial = line.left_side.as_poly(symbol)
        if polynomial is not None and polynomial.degree() == 2:
            return True
    return False


def _needs_expansion(expr) -> bool:
    if expr.is_Pow and expr.exp.is_integer and expr.exp > 1:
        return True
    if hasattr(expr, "atoms"):
        return any(arg.is_Pow and arg.exp.is_integer and arg.exp > 1 for arg in expr.atoms())
    return False


def _needs_cancellation(expr) -> bool:
    if expr.is_Mul:
        return any(arg.is_Pow and arg.exp.is_Rational for arg in expr.args)
    return False


def _fraction_parts(expr):
    if expr.is_Pow and expr.exp == -1 and expr.base.is_Integer:
        return (S.One, expr.base)
    if expr.is_Mul and not expr.free_symbols:
        numerator = S.One
        denominator = None
        for factor in expr.args:
            if factor.is_Integer:
                numerator = factor
            elif factor.is_Pow and factor.exp == -1 and factor.base.is_Integer:
                denominator = factor.base
        if denominator is not None:
            return (numerator, denominator)
    return None


def _is_zero_denominator_fraction(expr) -> bool:
    parts = _fraction_parts(expr)
    return parts is not None and parts[1] == 0


def _radical_parts(expr):
    if expr.is_Pow and expr.exp == S.Half and expr.base.is_Integer and expr.base > 0:
        return (expr.base,)
    if expr.is_Mul and not expr.free_symbols:
        for factor in expr.args:
            if factor.is_Pow and factor.exp == S.Half and factor.base.is_Integer and factor.base > 0:
                return (factor.base,)
    return None


def _is_simplest(expr):
    fraction = _fraction_parts(expr)
    if fraction is not None:
        numerator, denominator = fraction
        return denominator != 0 and abs(denominator) != 1 and gcd(numerator, denominator) == 1
    radical = _radical_parts(expr)
    if radical is not None:
        (radicand,) = radical
        return radicand != 1 and all(exponent < 2 for exponent in factorint(radicand).values())
    return None


def _expression_contains_power_term(line: ParsedExpression) -> bool:
    expr = line.expression
    if not expr.free_symbols:
        return False
    terms = expr.args if isinstance(expr, Add) else (expr,)
    return any(term.is_Pow or (term.is_Mul and any(factor.is_Pow for factor in term.args)) for term in terms)


EquationRule = tuple[Callable[[ParsedEquation], bool], str]
ExpressionRule = tuple[Callable[[ParsedExpression], bool], str]

_equation_rules: tuple[EquationRule, ...] = (
    (_is_factor_form_equation, "solve_factor_form"),
    (lambda line: not _has_single_unknown(line), "simplify_expression"),
    (_either_side(_contains_trig), "solve_trig"),
    (_either_side(_contains_exp), "solve_exp_log"),
    (_either_side(_contains_log), "solve_exp_log"),
    (_either_side(_contains_sqrt), "solve_radical"),
    (_is_quadratic_equation, "solve_quadratic"),
)


def _is_complex_number(line: ParsedExpression) -> bool:
    return I in line.expression.atoms()


def _is_numeric_awaiting_equals(line: ParsedExpression) -> bool:
    return not line.expression.free_symbols and not line.has_trailing_equals


_expression_rules: tuple[ExpressionRule, ...] = (
    (_is_complex_number, "convert_polar"),
    (_is_numeric_awaiting_equals, "awaiting_trailing_equals"),
    (lambda line: _is_zero_denominator_fraction(line.expression), "undefined_result"),
    (lambda line: _is_simplest(line.expression) is False, "simplify_expression"),
    (lambda line: _is_simplest(line.expression) is True, "convert_to_decimal"),
    (lambda line: _needs_expansion(line.expression), "expand_expression"),
    (_expression_contains_power_term, "factor_expression"),
    (lambda line: _needs_cancellation(line.expression), "cancel_expression"),
)


_equation_transforms = {
    "simplify_expression": expression_transforms.simplify_equation,
    "factor_expression": expression_transforms.factor_equation,
    "expand_expression": expression_transforms.expand_equation,
    "cancel_expression": expression_transforms.cancel_equation,
}

_expression_transforms = {
    "simplify_expression": expression_transforms.simplify_expression,
    "factor_expression": expression_transforms.factor_expression,
    "expand_expression": expression_transforms.expand_expression,
    "cancel_expression": expression_transforms.cancel_expression,
    "convert_to_decimal": expression_transforms.convert_expression_to_decimal,
    "undefined_result": expression_transforms.suggest_undefined_result,
}

_expression_single_arg = {
    "convert_polar": complex_numbers.convert_rectangular_to_polar,
    "compute_magnitude": complex_numbers.compute_magnitude,
    "compute_phase": complex_numbers.compute_phase_angle,
    "euler_form": complex_numbers.express_in_euler_form,
}


def _compute_limit(line: ParsedExpression, variable_name: str) -> str:
    return calculus.compute_limit_at_point(line, variable_name, "0")


_calculus_ops = {
    "differentiate": calculus.differentiate_expression,
    "integrate": calculus.integrate_expression,
    "compute_limit": _compute_limit,
    "expand_taylor": calculus.expand_as_taylor_series,
}


def _execute_equation(line: ParsedEquation, operation: str) -> SuggestedNextLine:
    transform = _equation_transforms.get(operation)
    if transform is not None:
        return SuggestedNextLine(transform(line), operation)
    if not equation_solving.equation_contains_solvable_variable(line):
        return SuggestedNextLine("", operation, "equation has no variable to solve for")
    if equation_solving.is_equation_solved(line):
        return SuggestedNextLine("", operation, "equation is already solved")
    result = equation_solving.solve_equation(line)
    if not result:
        return SuggestedNextLine("", operation, "cannot solve")
    return SuggestedNextLine(result, operation)


def _execute_expression(line: ParsedExpression, operation: str) -> SuggestedNextLine:
    if operation == "awaiting_trailing_equals":
        return SuggestedNextLine("", operation, "write \"=\" to request a result")
    transform = _expression_transforms.get(operation)
    if transform is not None:
        return SuggestedNextLine(transform(line), operation)
    single_arg_func = _expression_single_arg.get(operation)
    if single_arg_func is not None:
        return SuggestedNextLine(single_arg_func(line), operation)
    calculus_func = _calculus_ops.get(operation)
    if calculus_func is not None:
        return SuggestedNextLine(calculus_func(line, _get_variable_name(line.expression)), operation)
    return SuggestedNextLine("", operation, "no operation matched the current line")


def _get_variable_name(expression) -> str:
    symbols = expression.free_symbols
    if symbols:
        return sorted(symbols, key=lambda symbol: symbol.name)[0].name
    return "x"
