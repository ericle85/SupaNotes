import re
from sympy import Expr, Eq, Symbol, E, I, pi, log, srepr
from sympy.core.relational import Relational
from sympy.parsing.latex import parse_latex
from sympy.parsing.latex.errors import LaTeXParsingError
from sympy.parsing.sympy_parser import (
    parse_expr,
    standard_transformations,
    implicit_multiplication_application,
)


class TranslationError(Exception):
    pass


_UNSUPPORTED_CONSTRUCT = re.compile(
    r"\\begin\{|\\mathbb|\\operatorname|\\left\s*\||\\in\b|\\subset|\\subseteq|\\cup|\\cap|\\nabla"
)

_DECORATOR_COMMANDS = r"vec|hat|dot|ddot|bar|tilde|overline|mathrm|text|mathbf|boldsymbol"

_LATEX_NORMALIZERS = (
    (re.compile(r"\\frac(\d)(\d)"), r"\\frac{\1}{\2}"),
    (re.compile(r"\\(?:" + _DECORATOR_COMMANDS + r")\{([^{}]*)\}"), r"\1"),
    (re.compile(r"\^\s*\\circ"), ""),
)

_GREEK_NAMES = (
    "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi "
    "omicron rho sigma tau upsilon phi chi psi omega"
).split()

_PLAIN_TEXT_SYMBOLS = {
    name: Symbol("lambda_" if name == "lambda" else name) for name in _GREEK_NAMES
}
_PLAIN_TEXT_SYMBOLS.update({name.capitalize(): Symbol(name.capitalize()) for name in _GREEK_NAMES})
_PLAIN_TEXT_SYMBOLS.update({"pi": pi, "e": E, "E": E, "I": I, "ln": log})

_PLAIN_TEXT_TRANSFORMS = standard_transformations + (implicit_multiplication_application,)


def _looks_like_latex(text: str) -> bool:
    if "\\" in text or "{" in text:
        return True
    return "^" in text and "**" not in text


def _normalize_latex(text: str) -> str:
    for pattern, replacement in _LATEX_NORMALIZERS:
        text = pattern.sub(replacement, text)
    return text


def _parse_plain_text(text: str) -> Expr:
    return parse_expr(
        text.strip(),
        local_dict=_PLAIN_TEXT_SYMBOLS,
        transformations=_PLAIN_TEXT_TRANSFORMS,
    )


def _translate_latex(text: str):
    try:
        return parse_latex(_normalize_latex(text))
    except (LaTeXParsingError, Exception) as parse_error:
        raise TranslationError(f"latex parse failed: {parse_error}") from parse_error


def _translate_plain_text(text: str):
    if text.count("=") > 1:
        raise TranslationError("line contains multiple equals signs")
    try:
        if "=" in text:
            left_text, right_text = text.split("=")
            return Eq(_parse_plain_text(left_text), _parse_plain_text(right_text), evaluate=False)
        return _parse_plain_text(text)
    except TranslationError:
        raise
    except Exception as parse_error:
        raise TranslationError(f"could not parse expression: {parse_error}") from parse_error


def translate_ctc_line_to_sympy(line_text: str):
    stripped_text = line_text.strip()
    if _UNSUPPORTED_CONSTRUCT.search(stripped_text):
        raise TranslationError(f"unsupported latex construct: {stripped_text!r}")
    if stripped_text.endswith("=") and stripped_text.count("=") == 1:
        return translate_ctc_line_to_sympy(stripped_text[:-1])
    if _looks_like_latex(stripped_text):
        return _translate_latex(stripped_text)
    return _translate_plain_text(stripped_text)


def _self_check() -> None:
    def structure(expr) -> str:
        return srepr(expr)

    assert structure(translate_ctc_line_to_sympy(r"\frac{\alpha}{\beta}")) == structure(
        Symbol("alpha") / Symbol("beta")
    )
    assert structure(translate_ctc_line_to_sympy(r"e^{i\pi} + 1 = 0").lhs) == structure(
        Symbol("e") ** (Symbol("i") * Symbol("pi")) + 1
    )
    assert isinstance(translate_ctc_line_to_sympy(r"\sin(\theta) = \frac{1}{2}"), Relational)
    assert structure(translate_ctc_line_to_sympy(r"\vec{v}")) == structure(Symbol("v"))
    assert structure(translate_ctc_line_to_sympy("2*x + 3 = 11").lhs) == structure(2 * Symbol("x") + 3)
    assert structure(translate_ctc_line_to_sympy("(x+1)(x-2)")) == structure((Symbol("x") + 1) * (Symbol("x") - 2))
    for unsupported in (r"\begin{matrix} a & b \\ c & d \end{matrix}", r"x \in \mathbb{R}"):
        try:
            translate_ctc_line_to_sympy(unsupported)
            raise AssertionError(f"expected rejection: {unsupported!r}")
        except TranslationError:
            pass
    print("ctc_to_autosuggest_translator self-check passed")


if __name__ == "__main__":
    _self_check()
