from dataclasses import dataclass
from typing import Callable
from sympy import Add, Pow, sin, cos, tan, exp, log, factorint, gcd, I, N, S
from sympy.core.alphabets import greeks

from autocomplete.document_context_model import DocumentContext
from autocomplete.document_line_parser import ParsedEquation, ParsedExpression, UnparsableLine
from autocomplete.math_operations import ClassifiedIntent, MathOperation
from autocomplete.math_engine import (
    equation_solving,
    expression_transforms,
    calculus,
    complex_numbers,
    linear_algebra,
    transforms,
)


@dataclass(frozen=True)
class SuggestedNextLine:
    suggested_text: str
    operation: MathOperation
    diagnostic_reason: str = ""

    @property
    def has_suggestion(self) -> bool:
        return self.diagnostic_reason == ""


def generate_next_line(context: DocumentContext, intent: ClassifiedIntent) -> SuggestedNextLine:
    # intent is currently unused: the stub classifier is too coarse, so the CAS
    # resolves the real operation from the line's math structure. Re-introduce
    # when a real intent model can override _resolve_operation.
    line = context.current_line
    if isinstance(line, UnparsableLine):
        return SuggestedNextLine("", MathOperation.SIMPLIFY_EXPRESSION, line.parse_error_description)
    evaluated = _try_evaluate_trailing_equals(line, context.preceding_lines)
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


def _try_evaluate_trailing_equals(line, preceding_lines):
    if not isinstance(line, ParsedExpression) or not line.has_trailing_equals:
        return None
    resolved = line.expression.subs(_definitions_from_preceding(preceding_lines))
    numeric = N(resolved)
    if numeric.is_number and numeric.is_real is False:
        return None
    if resolved.free_symbols or not numeric.is_number:
        return SuggestedNextLine("", MathOperation.EVALUATE_NUMERIC, "expression has unknown or non-numeric terms")
    return SuggestedNextLine(_calculator_result_text(numeric), MathOperation.EVALUATE_NUMERIC)


def _resolve_equation(line: ParsedEquation) -> MathOperation:
    for matches, operation in _equation_rules:
        if matches(line):
            return operation
    return MathOperation.SOLVE_EQUATION_ONE_STEP


def _resolve_expression(line: ParsedExpression) -> MathOperation:
    for matches, operation in _expression_rules:
        if matches(line):
            return operation
    return MathOperation.SIMPLIFY_EXPRESSION


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


# Every Greek symbol is solvable: a multi-symbol equation routes to SOLVE targeting
# the highest-preference symbol. Chosen so the app can later let the user tap a
# suggestion and pick "solve for tau", "solve for omega", ... re-targeting the solve.
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


EquationRule = tuple[Callable[[ParsedEquation], bool], MathOperation]
ExpressionRule = tuple[Callable[[ParsedExpression], bool], MathOperation]

_equation_rules: tuple[EquationRule, ...] = (
    (_is_factor_form_equation, MathOperation.SOLVE_FACTOR_FORM),
    (lambda line: not _has_single_unknown(line), MathOperation.SIMPLIFY_EXPRESSION),
    (_either_side(_contains_trig), MathOperation.SOLVE_TRIG),
    (_either_side(_contains_exp), MathOperation.SOLVE_EXP_LOG),
    (_either_side(_contains_log), MathOperation.SOLVE_EXP_LOG),
    (_either_side(_contains_sqrt), MathOperation.SOLVE_RADICAL),
    (_is_quadratic_equation, MathOperation.SOLVE_QUADRATIC),
)


def _is_complex_number(line: ParsedExpression) -> bool:
    return I in line.expression.atoms()


def _is_numeric_awaiting_equals(line: ParsedExpression) -> bool:
    return not line.expression.free_symbols and not line.has_trailing_equals


_expression_rules: tuple[ExpressionRule, ...] = (
    (_is_complex_number, MathOperation.CONVERT_POLAR),
    (_is_numeric_awaiting_equals, MathOperation.AWAITING_TRAILING_EQUALS),
    (lambda line: _is_zero_denominator_fraction(line.expression), MathOperation.UNDEFINED_RESULT),
    (lambda line: _is_simplest(line.expression) is False, MathOperation.SIMPLIFY_EXPRESSION),
    (lambda line: _is_simplest(line.expression) is True, MathOperation.CONVERT_TO_DECIMAL),
    (lambda line: _needs_expansion(line.expression), MathOperation.EXPAND_EXPRESSION),
    (_expression_contains_power_term, MathOperation.FACTOR_EXPRESSION),
    (lambda line: _needs_cancellation(line.expression), MathOperation.CANCEL_EXPRESSION),
)


_equation_transforms = {
    MathOperation.SIMPLIFY_EXPRESSION: expression_transforms.simplify_equation,
    MathOperation.FACTOR_EXPRESSION: expression_transforms.factor_equation,
    MathOperation.EXPAND_EXPRESSION: expression_transforms.expand_equation,
    MathOperation.CANCEL_EXPRESSION: expression_transforms.cancel_equation,
}

_expression_transforms = {
    MathOperation.SIMPLIFY_EXPRESSION: expression_transforms.simplify_expression,
    MathOperation.FACTOR_EXPRESSION: expression_transforms.factor_expression,
    MathOperation.EXPAND_EXPRESSION: expression_transforms.expand_expression,
    MathOperation.CANCEL_EXPRESSION: expression_transforms.cancel_expression,
    MathOperation.CONVERT_TO_DECIMAL: expression_transforms.convert_expression_to_decimal,
    MathOperation.UNDEFINED_RESULT: expression_transforms.suggest_undefined_result,
}

_expression_single_arg = {
    MathOperation.CONVERT_POLAR: complex_numbers.convert_rectangular_to_polar,
    MathOperation.COMPUTE_MAGNITUDE: complex_numbers.compute_magnitude,
    MathOperation.COMPUTE_PHASE: complex_numbers.compute_phase_angle,
    MathOperation.EULER_FORM: complex_numbers.express_in_euler_form,
    MathOperation.COMPUTE_DETERMINANT: linear_algebra.compute_determinant,
    MathOperation.COMPUTE_INVERSE: linear_algebra.compute_inverse_matrix,
    MathOperation.COMPUTE_EIGENVALUES: linear_algebra.compute_eigenvalues,
    MathOperation.LAPLACE_TRANSFORM: transforms.compute_laplace_transform,
    MathOperation.INVERSE_LAPLACE: transforms.compute_inverse_laplace_transform,
    MathOperation.FOURIER_TRANSFORM: transforms.compute_fourier_transform,
}


def _compute_limit(line: ParsedExpression, variable_name: str) -> str:
    return calculus.compute_limit_at_point(line, variable_name, "0")


_calculus_ops = {
    MathOperation.DIFFERENTIATE: calculus.differentiate_expression,
    MathOperation.INTEGRATE: calculus.integrate_expression,
    MathOperation.COMPUTE_LIMIT: _compute_limit,
    MathOperation.EXPAND_TAYLOR: calculus.expand_as_taylor_series,
}


def _format_input_equation(line: ParsedEquation) -> str:
    return equation_solving._format_equation(line.left_side, line.right_side)


def _execute_equation(line: ParsedEquation, operation: MathOperation) -> SuggestedNextLine:
    transform = _equation_transforms.get(operation)
    if transform is not None:
        return SuggestedNextLine(transform(line), operation)
    if not equation_solving.equation_contains_solvable_variable(line):
        return SuggestedNextLine("", operation, "equation has no variable to solve for")
    if equation_solving.is_equation_solved(line):
        return SuggestedNextLine("", operation, "equation is already solved")
    step = equation_solving.generate_next_solving_step(line)
    if step.resulting_equation_text == _format_input_equation(line):
        return SuggestedNextLine("", operation, "cannot solve further")
    return SuggestedNextLine(step.resulting_equation_text, operation)


def _execute_expression(line: ParsedExpression, operation: MathOperation) -> SuggestedNextLine:
    if operation == MathOperation.AWAITING_TRAILING_EQUALS:
        return SuggestedNextLine("", operation, "write \"=\" to request a result")
    transform = _expression_transforms.get(operation)
    if transform is not None:
        return SuggestedNextLine(transform(line), operation)
    single_arg_func = _expression_single_arg.get(operation)
    if single_arg_func is not None:
        return SuggestedNextLine(single_arg_func(line), operation)
    if operation == MathOperation.RREF_STEP:
        step = linear_algebra.generate_next_rref_step(line)
        return SuggestedNextLine(step.resulting_matrix_text, operation)
    calculus_func = _calculus_ops.get(operation)
    if calculus_func is not None:
        return SuggestedNextLine(calculus_func(line, _get_variable_name(line.expression)), operation)
    return SuggestedNextLine("", operation, "no operation matched the current line")


def _get_variable_name(expression) -> str:
    symbols = expression.free_symbols
    if symbols:
        return sorted(symbols, key=lambda symbol: symbol.name)[0].name
    return "x"