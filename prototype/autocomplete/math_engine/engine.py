from dataclasses import dataclass
from autocomplete.document_context_model import DocumentContext
from autocomplete.document_line_parser import ParsedEquation, UnparsableLine
from autocomplete.math_operations import ClassifiedIntent, MathOperation
from autocomplete.math_engine.equation_solving import (
    generate_next_solving_step,
    equation_contains_solvable_variable,
)
from autocomplete.math_engine.expression_transforms import (
    simplify_expression, factor_expression,
)
from autocomplete.math_engine.calculus import (
    differentiate_expression,
    integrate_expression,
)
from autocomplete.math_engine.complex_numbers import (
    compute_magnitude,
    compute_phase_angle,
    convert_rectangular_to_polar,
)
from autocomplete.math_engine.linear_algebra import (
    compute_determinant,
    compute_inverse_matrix,
    compute_eigenvalues,
)
from autocomplete.math_engine.transforms import (
    compute_laplace_transform,
)


@dataclass(frozen=True)
class SuggestedNextLine:
    suggested_text: str
    diagnostic_reason: str = ""

    @property
    def has_suggestion(self) -> bool:
        return self.diagnostic_reason == ""


def generate_next_line(context: DocumentContext, intent: ClassifiedIntent) -> SuggestedNextLine:
    current_line = context.current_line
    if isinstance(current_line, UnparsableLine):
        return SuggestedNextLine("", current_line.parse_error_description)
    
    # Equation solving operations
    if intent.operation == MathOperation.SOLVE_EQUATION_ONE_STEP:
        return _suggest_equation_step(current_line)
    if intent.operation == MathOperation.SOLVE_QUADRATIC:
        return _suggest_equation_step(current_line)
    if intent.operation == MathOperation.SOLVE_FACTOR_FORM:
        return _suggest_equation_step(current_line)
    if intent.operation == MathOperation.SOLVE_TRIG:
        return _suggest_equation_step(current_line)
    if intent.operation == MathOperation.SOLVE_EXP_LOG:
        return _suggest_equation_step(current_line)
    if intent.operation == MathOperation.SOLVE_RADICAL:
        return _suggest_equation_step(current_line)
    
    # Expression transform operations
    if intent.operation == MathOperation.SIMPLIFY_EXPRESSION:
        if isinstance(current_line, ParsedEquation):
            return SuggestedNextLine(_simplify_equation(current_line))
        return SuggestedNextLine(simplify_expression(current_line))
    if intent.operation == MathOperation.FACTOR_EXPRESSION:
        if isinstance(current_line, ParsedEquation):
            return SuggestedNextLine(_factor_equation(current_line))
        return SuggestedNextLine(factor_expression(current_line))
    if intent.operation == MathOperation.EXPAND_EXPRESSION:
        return SuggestedNextLine(_expand_expression(current_line))
    if intent.operation == MathOperation.CANCEL_EXPRESSION:
        return SuggestedNextLine(_cancel_expression(current_line))
    
    # Calculus operations
    if intent.operation == MathOperation.DIFFERENTIATE:
        return SuggestedNextLine(_differentiate_expression(current_line))
    if intent.operation == MathOperation.INTEGRATE:
        return SuggestedNextLine(_integrate_expression(current_line))
    if intent.operation == MathOperation.COMPUTE_LIMIT:
        return SuggestedNextLine(_compute_limit(current_line))
    if intent.operation == MathOperation.EXPAND_TAYLOR:
        return SuggestedNextLine(_expand_taylor_series(current_line))
    
    # Complex number operations
    if intent.operation == MathOperation.CONVERT_POLAR:
        return SuggestedNextLine(_convert_to_polar(current_line))
    if intent.operation == MathOperation.COMPUTE_MAGNITUDE:
        return SuggestedNextLine(_compute_magnitude_val(current_line))
    if intent.operation == MathOperation.COMPUTE_PHASE:
        return SuggestedNextLine(_compute_phase_val(current_line))
    if intent.operation == MathOperation.EULER_FORM:
        return SuggestedNextLine(_euler_form(current_line))
    
    # Linear algebra operations
    if intent.operation == MathOperation.RREF_STEP:
        return SuggestedNextLine(_rref_step(current_line))
    if intent.operation == MathOperation.COMPUTE_DETERMINANT:
        return SuggestedNextLine(_compute_det(current_line))
    if intent.operation == MathOperation.COMPUTE_INVERSE:
        return SuggestedNextLine(_compute_inv(current_line))
    if intent.operation == MathOperation.COMPUTE_EIGENVALUES:
        return SuggestedNextLine(_compute_eigenval(current_line))
    
    # Transform operations
    if intent.operation == MathOperation.LAPLACE_TRANSFORM:
        return SuggestedNextLine(_compute_laplace(current_line))
    if intent.operation == MathOperation.INVERSE_LAPLACE:
        return SuggestedNextLine(_compute_inverse_laplace(current_line))
    if intent.operation == MathOperation.FOURIER_TRANSFORM:
        return SuggestedNextLine(_compute_fourier(current_line))
    
    return SuggestedNextLine("", "no operation matched the current line")


def _suggest_equation_step(line: ParsedEquation) -> SuggestedNextLine:
    if not equation_contains_solvable_variable(line):
        return SuggestedNextLine("", "equation has no variable to solve for")
    return SuggestedNextLine(generate_next_solving_step(line).resulting_equation_text)



def _expand_expression(line):
    from autocomplete.math_engine.expression_transforms import expand_expression
    return expand_expression(line)

def _cancel_expression(line):
    from autocomplete.math_engine.expression_transforms import cancel_expression
    return cancel_expression(line)

def _differentiate_expression(line):
    from autocomplete.math_engine.calculus import differentiate_expression
    return differentiate_expression(line, _get_variable_name(line.expression))

def _integrate_expression(line):
    from autocomplete.math_engine.calculus import integrate_expression
    return integrate_expression(line, _get_variable_name(line.expression))

def _compute_limit(line):
    from autocomplete.math_engine.calculus import compute_limit_at_point
    return compute_limit_at_point(line, _get_variable_name(line.expression), "0")

def _expand_taylor_series(line):
    from autocomplete.math_engine.calculus import expand_as_taylor_series
    return expand_as_taylor_series(line, _get_variable_name(line.expression))

def _convert_to_polar(line):
    from autocomplete.math_engine.complex_numbers import convert_rectangular_to_polar
    return convert_rectangular_to_polar(line)

def _compute_magnitude_val(line):
    from autocomplete.math_engine.complex_numbers import compute_magnitude
    return compute_magnitude(line)

def _compute_phase_val(line):
    from autocomplete.math_engine.complex_numbers import compute_phase_angle
    return compute_phase_angle(line)

def _euler_form(line):
    from autocomplete.math_engine.complex_numbers import express_in_euler_form
    return express_in_euler_form(line)

def _rref_step(line):
    from autocomplete.math_engine.linear_algebra import generate_next_rref_step
    step = generate_next_rref_step(line)
    return step.resulting_matrix_text

def _compute_det(line):
    return compute_determinant(line)

def _compute_inv(line):
    return compute_inverse_matrix(line)

def _compute_eigenval(line):
    return compute_eigenvalues(line)

def _compute_laplace(line):
    return compute_laplace_transform(line)

def _compute_inverse_laplace(line):
    from autocomplete.math_engine.transforms import compute_inverse_laplace_transform
    return compute_inverse_laplace_transform(line)

def _compute_fourier(line):
    from autocomplete.math_engine.transforms import compute_fourier_transform
    return compute_fourier_transform(line)

def _get_variable_name(expression):
    from sympy import Symbol
    symbols = expression.free_symbols
    if symbols:
        return sorted(symbols, key=lambda s: s.name)[0].name
    return "x"

def _suggest_equation_step(line):
    from autocomplete.math_engine.equation_solving import (
        generate_next_solving_step,
        equation_contains_solvable_variable,
    )
    if not equation_contains_solvable_variable(line):
        return SuggestedNextLine("", "equation has no variable to solve for")
    return SuggestedNextLine(generate_next_solving_step(line).resulting_equation_text)


def _simplify_equation(line):
    from autocomplete.math_engine.expression_transforms import simplify_equation
    return simplify_equation(line)


def _factor_equation(line):
    from autocomplete.math_engine.expression_transforms import factor_equation
    return factor_equation(line)


def _expand_equation(line):
    from autocomplete.math_engine.expression_transforms import expand_equation
    return expand_equation(line)