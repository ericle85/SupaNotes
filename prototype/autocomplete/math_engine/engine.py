from sympy import solve, Eq
from sympy.core.relational import Relational

from math_engine.ctc_to_autosuggest_translator import (
    ends_with_bare_equals,
    translate_ctc_line_to_sympy,
)
from math_engine.util import format_result


def do_autosuggestion(raw_ctc_string: str, solve_for=None):
    sympy_expression = translate_ctc_line_to_sympy(raw_ctc_string)
    free = sympy_expression.free_symbols

    if isinstance(sympy_expression, Relational) and len(free) >= 1:
        suggestion = _solve_equation(sympy_expression, free, solve_for)
        if suggestion is None:
            return None, "N/A"
        return suggestion, PLACEMENT_SOLVE

    if not ends_with_bare_equals(raw_ctc_string):
        return None, "N/A"

    if free:
        return None, "N/A"

    result = sympy_expression.simplify()
    return format_result(sympy_expression, result), "append"


def _solve_equation(equation, free_symbols, solve_for=None):
    if solve_for is not None:
        target = solve_for
    elif len(free_symbols) == 1:
        target = next(iter(free_symbols))
    else:
        return None

    solutions = solve(equation, target)
    if not solutions:
        return None

    formatted_values = [format_result(s, s.simplify()) for s in solutions]
    return f"{target}={', '.join(formatted_values)}"


PLACEMENT_SOLVE = "alignWithEqualSignAbove"


def _self_check():
    assert do_autosuggestion("2+2=") == ("4", "append")
    assert do_autosuggestion(r"\frac{10}{2}=") == ("5", "append")
    assert do_autosuggestion("3*4+1=") == ("13", "append")
    assert do_autosuggestion("2+x=")[0] is None
    assert do_autosuggestion("2+2")[0] is None
    assert do_autosuggestion(r"\frac{6}{9}=") == ("2/3", "append")
    assert do_autosuggestion(r"\frac{2}{3}=") == ("0.667", "append")
    assert do_autosuggestion(r"\frac{1}{2}=") == ("0.5", "append")

    assert do_autosuggestion("2x=8") == ("x=4", PLACEMENT_SOLVE)
    assert do_autosuggestion("x^2=9") == ("x=-3, 3", PLACEMENT_SOLVE)
    assert do_autosuggestion("x^2+2x+1=0") == ("x=-1", PLACEMENT_SOLVE)
    assert do_autosuggestion("2x-8=")[0] is None

    from sympy import Symbol
    assert do_autosuggestion("2x+y=10", solve_for=Symbol("x")) == ("x=5 - y/2", PLACEMENT_SOLVE)

    print("engine self-check passed")


if __name__ == "__main__":
    _self_check()