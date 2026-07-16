from dataclasses import dataclass
from typing import Optional
from sympy import (
    Add, Expr, Integer, Symbol, S, solveset,
    sin, cos, tan, exp, log, sqrt,
    asin, acos, atan, E,
)
from sympy.sets import EmptySet
from sympy.core.alphabets import greeks
from autocomplete.document_line_parser import ParsedEquation
from autocomplete.math_engine.latex_format import to_latex


_preferred_unknown_variable_names = (
    "x", "y", "z", "t", "w", "u", "v", "s", "r", "q", "p", "n", "m", "k",
) + greeks


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
        _divide_out_leading_numeric_factor,
        _divide_both_sides_by_coefficient,
        _divide_by_power_coefficient,
        _extract_radical_solution,
        _extract_trig_solution,
        _extract_exp_log_solution,
        _extract_quadratic_solution,
        _extract_factored_form_solution,
        _expand_factored_form_equation,
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


def _divide_out_leading_numeric_factor(
    left_side: Expr, right_side: Expr, variable: Symbol
) -> Optional[EquationStep]:
    coefficient, remaining_factor = left_side.as_coeff_Mul()
    if not coefficient.is_number or coefficient == 1 or coefficient == 0:
        return None
    if not remaining_factor.is_Add or variable not in remaining_factor.free_symbols:
        return None
    return EquationStep(
        resulting_equation_text=_format_equation(remaining_factor, right_side / coefficient),
        move_description=f"divide both sides by {coefficient}",
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
    """Handle x**n = c → x = c^(1/n), returning all real solutions."""
    if not right_side.is_number:
        return None
    if not left_side.is_Pow or left_side.base != variable or not left_side.exp.is_number:
        return None
    n = left_side.exp

    # Use solveset for all real roots (includes negative solutions)
    equation = variable**n - right_side
    solutions = solveset(equation, variable, domain=S.Reals)

    if solutions == EmptySet:
        return EquationStep(
            resulting_equation_text=f"{to_latex(variable)} = \\emptyset",
            move_description=f"no real solution to x**{n} = {right_side}",
            is_fully_solved=True,
        )

    solution_list = sorted(list(solutions), key=lambda s: float(s) if s.is_real else float('-inf'))
    solutions_text = ", ".join(to_latex(s) for s in solution_list)
    move_desc = "take the square root" if n == 2 else f"take the {n}-th root"
    return EquationStep(
        resulting_equation_text=f"{to_latex(variable)} = {solutions_text}",
        move_description=move_desc,
        is_fully_solved=True,
    )




def _extract_trig_solution(
    left_side: Expr, right_side: Expr, variable: Symbol
) -> Optional[EquationStep]:
    """Handle trig equations like sin(x) = 0, cos(x) = 0.5"""
    # Check if left side is a trig function
    if left_side.func in (sin, cos, tan):
        func_name = left_side.func.__name__
        # Extract the argument
        arg = left_side.args[0]
        if arg == variable:
            # Get the principal value
            if func_name == 'sin':
                val = asin(right_side)
            elif func_name == 'cos':
                val = acos(right_side)
            elif func_name == 'tan':
                val = atan(right_side)
            return EquationStep(
                resulting_equation_text=f"{to_latex(variable)} = {to_latex(val)}",
                move_description=f"take the {func_name} inverse",
                is_fully_solved=True,
            )
    return None


def _extract_exp_log_solution(
    left_side: Expr, right_side: Expr, variable: Symbol
) -> Optional[EquationStep]:
    """Handle exponential/logarithmic equations like e^x = 2, ln(x) = 3"""
    # Check if left side is exp or log
    if left_side.func in (exp,):
        arg = left_side.args[0]
        if arg == variable:
            # e^x = c → x = ln(c)
            val = log(right_side)
            return EquationStep(
                resulting_equation_text=f"{to_latex(variable)} = {to_latex(val)}",
                move_description="take the natural logarithm",
                is_fully_solved=True,
            )
    elif left_side.func in (log,):
        arg = left_side.args[0]
        if arg == variable:
            base = left_side.args[1] if len(left_side.args) > 1 else E
            val = base ** right_side
            return EquationStep(
                resulting_equation_text=f"{to_latex(variable)} = {to_latex(val)}",
                move_description="exponentiate both sides",
                is_fully_solved=True,
            )
    # Check for e**x form (Pow with base E)
    elif left_side.is_Pow and left_side.base == E and left_side.exp == variable:
        val = log(right_side)
        return EquationStep(
            resulting_equation_text=f"{to_latex(variable)} = {to_latex(val)}",
            move_description="take the natural logarithm",
            is_fully_solved=True,
        )
    return None


def _extract_radical_solution(
    left_side: Expr, right_side: Expr, variable: Symbol
) -> Optional[EquationStep]:
    """Handle radical equations like sqrt(x) = 3"""
    if left_side == sqrt(variable):
        val = right_side**2
        return EquationStep(
            resulting_equation_text=f"{to_latex(variable)} = {to_latex(val)}",
            move_description="square both sides",
            is_fully_solved=True,
        )
    return None


def _extract_quadratic_solution(
    left_side: Expr, right_side: Expr, variable: Symbol
) -> Optional[EquationStep]:
    """Handle quadratic equations using solveset for all roots"""
    # Only if left side is a quadratic in variable
    if left_side.is_Pow:
        # x**2 = c case (already handled by _extract_root_if_possible)
        return None
    if left_side.is_Add or left_side.is_Mul:
        # Check if it's a quadratic expression
        # Try to solve using solveset for quadratic
        equation = left_side - right_side
        solutions = solveset(equation, variable, domain=S.Reals)
        from sympy.sets import EmptySet
        if solutions != EmptySet and len(solutions) <= 2:
            solution_list = sorted(list(solutions), key=lambda s: float(s) if s.is_real else float('-inf'))
            solutions_text = ", ".join(to_latex(s) for s in solution_list)
            return EquationStep(
                resulting_equation_text=f"{to_latex(variable)} = {solutions_text}",
                move_description="apply the quadratic formula",
                is_fully_solved=True,
            )
    return None




def _extract_factored_form_solution(
    left_side: Expr, right_side: Expr, variable: Symbol
) -> Optional[EquationStep]:
    """Handle (x+a)(x+b) = 0 → x = -a or x = -b"""
    if right_side != 0:
        return None
    if not left_side.is_Mul:
        return None
    # Get all factors
    factors = left_side.args
    binomial_factors = [f for f in factors if f.is_Add or (f.is_Mul and variable in f.free_symbols)]
    if not binomial_factors or len(binomial_factors) < 2:
        return None
    solutions = []
    from sympy.sets import EmptySet
    for factor in binomial_factors:
        sol = solveset(factor, variable, domain=S.Reals)
        if sol != EmptySet:
            for s in sorted(list(sol), key=lambda x: float(x) if x.is_real else float('-inf')):
                solutions.append(to_latex(s))
    if solutions:
        return EquationStep(
            resulting_equation_text=f"{to_latex(variable)} = {' or '.join(solutions)}",
            move_description="apply the zero product property",
            is_fully_solved=True,
        )
    return None

def _expand_factored_form_equation(
    left_side: Expr, right_side: Expr, variable: Symbol
) -> Optional[EquationStep]:
    """Handle factored form equations like (x+1)(x-2) = 0"""
    # Check if left side is a product of binomials
    if left_side.is_Mul:
        # Check if it's a product of terms
        for arg in left_side.args:
            if arg.is_Add and len(arg.args) == 2 and variable in arg.free_symbols:
                # Found a binomial factor = variable + constant
                pass
        # For factored form = 0, apply zero product property
        if right_side == 0:
            # Get all the factors
            factors = left_side.args if left_side.is_Mul else [left_side]
            binomial_factors = []
            for factor in factors:
                if factor.is_Add or (factor.is_Mul and variable in factor.free_symbols):
                    binomial_factors.append(factor)
            if binomial_factors:
                # Generate solutions for each factor
                solutions = []
                for factor in binomial_factors:
                    # Solve factor = 0 for variable
                    sol = solveset(factor, variable, domain=S.Reals)
                    if sol != EmptySet:
                        for s in sorted(list(sol), key=lambda x: float(x) if x.is_real else float('-inf')):
                            solutions.append(to_latex(s))
                if solutions:
                    solutions_text = " or ".join(solutions)
                    return EquationStep(
                        resulting_equation_text=f"{to_latex(variable)} = {solutions_text}",
                        move_description="apply the zero product property",
                        is_fully_solved=True,
                    )
    return None


def _format_equation(left_side: Expr, right_side: Expr) -> str:
    return f"{to_latex(left_side)} = {to_latex(right_side)}"
