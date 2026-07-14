from dataclasses import dataclass
from typing import Optional
from sympy import Add, Expr, Integer, Symbol
from autocomplete.document_line_parser import ParsedEquation


_preferred_unknown_variable_names = ("x", "y", "z", "t", "w", "u", "v", "s", "r", "q", "p", "n", "m", "k")


@dataclass(frozen=True)
class EquationStep:
    resulting_equation_text: str
    move_description: str
    is_fully_solved: bool


def equation_contains_solvable_variable(line: ParsedEquation) -> bool:
    return bool(line.left_side.free_symbols | line.right_side.free_symbols)


def generate_next_solving_step(line: ParsedEquation) -> EquationStep:
    variable = _select_target_variable(line)
    left_side = line.left_side
    right_side = line.right_side

    for build_step in (
        _move_variable_terms_from_right_to_left,
        _move_constant_terms_from_left_to_right,
        _divide_both_sides_by_coefficient,
        _divide_by_power_coefficient,
        _extract_root_if_possible,
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
    symbols_by_name = {symbol.name: symbol for symbol in all_symbols}
    for preferred_name in _preferred_unknown_variable_names:
        if preferred_name in symbols_by_name:
            return symbols_by_name[preferred_name]
    return sorted(all_symbols, key=lambda symbol: symbol.name)[0]


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


def _divide_by_power_coefficient(
    left_side: Expr, right_side: Expr, variable: Symbol
) -> Optional[EquationStep]:
    """Handle a*x**n = c → x**n = c/a (first step toward root extraction)."""
    power_term = None
    args = left_side.args if left_side.is_Mul else [left_side]
    for arg in args:
        if arg.is_Pow and arg.base == variable and arg.exp.is_number and arg.exp > 1:
            power_term = arg
            break
    if power_term is None:
        return None
    coeff = left_side / power_term
    if coeff == 1 or coeff == 0:
        return None
    return EquationStep(
        resulting_equation_text=_format_equation(left_side / coeff, right_side / coeff),
        move_description=f"divide both sides by {coeff}",
        is_fully_solved=False,
    )


def _extract_root_if_possible(
    left_side: Expr, right_side: Expr, variable: Symbol
) -> Optional[EquationStep]:
    """Handle x**n = c → x = c^(1/n)."""
    if not right_side.is_number:
        return None
    if left_side.is_Pow and left_side.base == variable and left_side.exp.is_number:
        n = left_side.exp
        root_val = right_side ** (Integer(1) / n)
        result_text = f"{variable} = {root_val}"
        move_desc = "take the square root" if n == 2 else f"take the {n}-th root"
        return EquationStep(
            resulting_equation_text=result_text,
            move_description=move_desc,
            is_fully_solved=True,
        )
    return None


def _format_equation(left_side: Expr, right_side: Expr) -> str:
    return f"{left_side} = {right_side}"
