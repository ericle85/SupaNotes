from dataclasses import dataclass
from typing import Optional
from sympy import Add, Expr, Symbol
from autocomplete.document_line_parser import ParsedEquation


@dataclass(frozen=True)
class EquationStep:
    resulting_equation_text: str
    move_description: str
    is_fully_solved: bool


def generate_next_solving_step(line: ParsedEquation) -> EquationStep:
    variable = _select_target_variable(line)
    left_side = line.left_side
    right_side = line.right_side

    for build_step in (
        _move_variable_terms_from_right_to_left,
        _move_constant_terms_from_left_to_right,
        _divide_both_sides_by_coefficient,
    ):
        step = build_step(left_side, right_side, variable)
        if step is not None:
            return step

    return EquationStep(
        resulting_equation_text=_format_equation(left_side, right_side),
        move_description="already solved",
        is_fully_solved=True,
    )


def _select_target_variable(line: ParsedEquation) -> Symbol:
    all_symbols = line.left_side.free_symbols | line.right_side.free_symbols
    ordered_symbols = sorted(all_symbols, key=lambda symbol: symbol.name)
    return ordered_symbols[0]


def _split_variable_and_constant_terms(expression: Expr, variable: Symbol):
    terms = expression.args if isinstance(expression, Add) else (expression,)
    variable_terms = [term for term in terms if variable in term.free_symbols]
    constant_terms = [term for term in terms if variable not in term.free_symbols]
    return variable_terms, constant_terms


def _move_variable_terms_from_right_to_left(
    left_side: Expr, right_side: Expr, variable: Symbol
) -> Optional[EquationStep]:
    right_variable_terms, _ = _split_variable_and_constant_terms(right_side, variable)
    if not right_variable_terms:
        return None
    moved_terms = Add(*right_variable_terms)
    return EquationStep(
        resulting_equation_text=_format_equation(left_side - moved_terms, right_side - moved_terms),
        move_description=f"subtract {moved_terms} from both sides",
        is_fully_solved=False,
    )


def _move_constant_terms_from_left_to_right(
    left_side: Expr, right_side: Expr, variable: Symbol
) -> Optional[EquationStep]:
    _, left_constant_terms = _split_variable_and_constant_terms(left_side, variable)
    if not left_constant_terms:
        return None
    moved_terms = Add(*left_constant_terms)
    return EquationStep(
        resulting_equation_text=_format_equation(left_side - moved_terms, right_side - moved_terms),
        move_description=f"subtract {moved_terms} from both sides",
        is_fully_solved=False,
    )


def _divide_both_sides_by_coefficient(
    left_side: Expr, right_side: Expr, variable: Symbol
) -> Optional[EquationStep]:
    coefficient = left_side.coeff(variable, 1)
    if coefficient == 1 or coefficient == 0:
        return None
    return EquationStep(
        resulting_equation_text=_format_equation(left_side / coefficient, right_side / coefficient),
        move_description=f"divide both sides by {coefficient}",
        is_fully_solved=False,
    )


def _format_equation(left_side: Expr, right_side: Expr) -> str:
    return f"{left_side} = {right_side}"
