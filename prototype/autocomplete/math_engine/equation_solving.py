from sympy import Symbol, solve
from sympy.core.alphabets import greeks
from autocomplete.document_line_parser import ParsedEquation
from autocomplete.math_engine.latex_format import to_latex


_preferred_unknown_variable_names = (
    "x", "y", "z", "t", "w", "u", "v", "s", "r", "q", "p", "n", "m", "k",
) + greeks


def equation_contains_solvable_variable(line: ParsedEquation) -> bool:
    return bool(line.left_side.free_symbols | line.right_side.free_symbols)


def is_equation_solved(line: ParsedEquation) -> bool:
    variable = _select_target_variable(line)
    left, right = line.left_side, line.right_side
    isolated_left = left == variable and variable not in right.free_symbols
    isolated_right = right == variable and variable not in left.free_symbols
    return isolated_left or isolated_right


def solve_equation(line: ParsedEquation) -> str:
    variable = _select_target_variable(line)
    solutions = solve(line.left_side - line.right_side, variable)
    if not solutions:
        return ""
    sorted_solutions = sorted(solutions, key=_solution_sort_key)
    solutions_text = ", ".join(to_latex(s) for s in sorted_solutions)
    return f"{to_latex(variable)} = {solutions_text}"


def _solution_sort_key(solution):
    try:
        return (0, float(solution))
    except (TypeError, ValueError):
        return (1, str(solution))


def _select_target_variable(line: ParsedEquation) -> Symbol:
    all_symbols = line.left_side.free_symbols | line.right_side.free_symbols
    symbols_by_name = {symbol.name: symbol for symbol in all_symbols}
    for preferred_name in _preferred_unknown_variable_names:
        if preferred_name in symbols_by_name:
            return symbols_by_name[preferred_name]
    return sorted(all_symbols, key=lambda symbol: symbol.name)[0]


def _format_equation(left_side, right_side) -> str:
    return f"{to_latex(left_side)} = {to_latex(right_side)}"
