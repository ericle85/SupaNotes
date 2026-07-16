from dataclasses import dataclass
from typing import Callable
from sympy import Add, Symbol, sin, cos, tan, exp, log, sqrt, factorint, gcd, I, E, S

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
    operation = _resolve_operation(line)
    if isinstance(line, ParsedEquation):
        return _execute_equation(line, operation)
    return _execute_expression(line, operation)


_SINGLE_VAR_INDICATORS = ("x", "y", "z", "t", "w")


def _resolve_operation(line) -> MathOperation:
    if isinstance(line, ParsedEquation):
        return _resolve_equation(line)
    if isinstance(line, ParsedExpression):
        return _resolve_expression(line)
    return MathOperation.SIMPLIFY_EXPRESSION


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


def _contains_func(*funcs) -> Callable:
    def check(expr) -> bool:
        if hasattr(expr, "func") and expr.func in funcs:
            return True
        if hasattr(expr, "atoms"):
            return any(hasattr(atom, "func") and atom.func in funcs for atom in expr.atoms())
        return False
    return check


_contains_trig = _contains_func(sin, cos, tan)
_contains_log = _contains_func(log)
_exp_func_check = _contains_func(exp)


def _contains_exp(expr) -> bool:
    return _exp_func_check(expr) or (expr.is_Pow and expr.base == E)


def _contains_sqrt(expr) -> bool:
    if expr.is_Pow and expr.exp == S.Half:
        return True
    if hasattr(expr, "func") and expr.func == sqrt:
        return True
    if hasattr(expr, "atoms"):
        return any(atom.is_Pow and atom.exp == S.Half for atom in expr.atoms())
    return False


def _has_single_unknown(line: ParsedEquation) -> bool:
    all_symbols = line.left_side.free_symbols | line.right_side.free_symbols
    if len(all_symbols) <= 1:
        return True
    names = {symbol.name for symbol in all_symbols}
    if any(symbol.name == "x" for symbol in all_symbols):
        return True
    if any(len(name) > 1 and name[0].islower() and name.isalpha() for name in names):
        return False
    return any(indicator in names for indicator in _SINGLE_VAR_INDICATORS)


def _is_factor_form_equation(line: ParsedEquation) -> bool:
    if line.right_side != 0 or not line.left_side.is_Mul:
        return False
    binomial_factors = [
        factor for factor in line.left_side.args
        if factor.is_Add or (factor.is_Mul and len(factor.free_symbols) > 0)
    ]
    return len(binomial_factors) >= 2


def _is_quadratic_equation(line: ParsedEquation) -> bool:
    symbols = line.left_side.free_symbols | line.right_side.free_symbols
    return _is_quadratic(line.left_side, symbols)


def _is_quadratic(expr, symbols) -> bool:
    for symbol in symbols:
        polynomial = expr.as_poly(symbol) if expr.as_poly(symbol) else None
        degree = polynomial.degree() if polynomial else -1
        if degree == 2:
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


def _fraction_is_already_simplest(parts) -> bool:
    numerator, denominator = parts
    return denominator != 0 and abs(denominator) != 1 and gcd(numerator, denominator) == 1


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


def _radical_is_already_simplest(parts) -> bool:
    (radicand,) = parts
    return radicand != 1 and all(exponent < 2 for exponent in factorint(radicand).values())


def _is_reducible_literal(expr) -> bool:
    fraction = _fraction_parts(expr)
    if fraction is not None:
        return fraction[1] != 0 and not _fraction_is_already_simplest(fraction)
    radical = _radical_parts(expr)
    if radical is not None:
        return not _radical_is_already_simplest(radical)
    return False


def _is_simplest_literal(expr) -> bool:
    fraction = _fraction_parts(expr)
    if fraction is not None:
        return _fraction_is_already_simplest(fraction)
    radical = _radical_parts(expr)
    if radical is not None:
        return _radical_is_already_simplest(radical)
    return False


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

_expression_rules: tuple[ExpressionRule, ...] = (
    (lambda line: I in line.expression.atoms(), MathOperation.CONVERT_POLAR),
    (
        lambda line: not line.expression.free_symbols and not line.has_trailing_equals,
        MathOperation.AWAITING_TRAILING_EQUALS,
    ),
    (lambda line: _is_zero_denominator_fraction(line.expression), MathOperation.UNDEFINED_RESULT),
    (lambda line: _is_reducible_literal(line.expression), MathOperation.SIMPLIFY_EXPRESSION),
    (lambda line: _is_simplest_literal(line.expression), MathOperation.CONVERT_TO_DECIMAL),
    (lambda line: _needs_expansion(line.expression), MathOperation.EXPAND_EXPRESSION),
    (lambda line: _expression_contains_power_term(line), MathOperation.FACTOR_EXPRESSION),
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


def _execute_equation(line: ParsedEquation, operation: MathOperation) -> SuggestedNextLine:
    transform = _equation_transforms.get(operation)
    if transform is not None:
        return SuggestedNextLine(transform(line), operation)
    if not equation_solving.equation_contains_solvable_variable(line):
        return SuggestedNextLine("", operation, "equation has no variable to solve for")
    step = equation_solving.generate_next_solving_step(line)
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