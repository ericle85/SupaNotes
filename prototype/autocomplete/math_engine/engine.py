from math_engine.ctc_to_autosuggest_translator import (
    ends_with_bare_equals,
    translate_ctc_line_to_sympy,
)
from math_engine.util import format_result


def do_autosuggestion(raw_ctc_string: str) -> str:
    sympy_expression = translate_ctc_line_to_sympy(raw_ctc_string)

    if not ends_with_bare_equals(raw_ctc_string):
        return None

    if sympy_expression.free_symbols:
        return None

    result = sympy_expression.simplify()
    return format_result(sympy_expression, result)


def _self_check():
    assert do_autosuggestion("2+2=") == "4"
    assert do_autosuggestion(r"\frac{10}{2}=") == "5"
    assert do_autosuggestion("3*4+1=") == "13"
    assert do_autosuggestion("2+x=") is None
    assert do_autosuggestion("2+2") is None
    assert do_autosuggestion(r"\frac{6}{9}=") == "2/3"
    assert do_autosuggestion(r"\frac{2}{3}=") == "0.667"
    assert do_autosuggestion(r"\frac{1}{2}=") == "0.5"
    print("engine self-check passed")


if __name__ == "__main__":
    _self_check()