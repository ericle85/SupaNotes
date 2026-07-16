import re
from sympy import Symbol, Eq, srepr
from sympy.core.relational import Relational
from sympy.parsing.latex import parse_latex
from sympy.parsing.latex.errors import LaTeXParsingError


class TranslationError(Exception):
    pass


_UNSUPPORTED_CONSTRUCT = re.compile(
    r"\\begin\{|\\mathbb|\\operatorname|\\left\s*\||\\in\b|\\subset|\\subseteq|\\cup|\\cap|\\nabla"
)

_DECORATOR_COMMANDS = r"vec|hat|dot|ddot|bar|tilde|overline|mathrm|text|mathbf|boldsymbol"

_BARE_FUNCTIONS = (
    "arcsin|arccos|arctan|sinh|cosh|tanh|coth|sin|cos|tan|cot|sec|csc|"
    "log|ln|exp|lim|max|min|gcd|det|deg|dim|arg"
)

_LATEX_NORMALIZERS = (
    (re.compile(r"\\frac(\d)(\d)"), r"\\frac{\1}{\2}"),
    (re.compile(r"\\(?:" + _DECORATOR_COMMANDS + r")\{([^{}]*)\}"), r"\1"),
    (re.compile(r"\^\s*\\circ"), ""),
    (re.compile(r"(?<![A-Za-z\\])(?:" + _BARE_FUNCTIONS + r")(?=\s*\()"), lambda m: "\\" + m.group(0)),
)


def _normalize_latex(text: str) -> str:
    for pattern, replacement in _LATEX_NORMALIZERS:
        text = pattern.sub(replacement, text)
    return text


def ends_with_bare_equals(text: str) -> bool:
    stripped_text = text.strip()
    return stripped_text.endswith("=") and stripped_text.count("=") == 1


def _parse_latex(text: str):
    try:
        return parse_latex(text)
    except (LaTeXParsingError, Exception) as parse_error:
        raise TranslationError(f"latex parse failed: {parse_error}") from parse_error


def translate_ctc_line_to_sympy(line_text: str):
    stripped_text = line_text.strip()
    if _UNSUPPORTED_CONSTRUCT.search(stripped_text):
        raise TranslationError(f"unsupported latex construct: {stripped_text!r}")
    if ends_with_bare_equals(stripped_text):
        return translate_ctc_line_to_sympy(stripped_text[:-1])
    normalized_text = _normalize_latex(stripped_text)
    if normalized_text.count("=") > 1:
        raise TranslationError("line contains multiple equals signs")
    if "=" in normalized_text:
        left_text, right_text = normalized_text.split("=")
        return Eq(_parse_latex(left_text), _parse_latex(right_text), evaluate=False)
    return _parse_latex(normalized_text)


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
    assert structure(translate_ctc_line_to_sympy("2x + 3 = 11").lhs) == structure(2 * Symbol("x") + 3)
    assert structure(translate_ctc_line_to_sympy("(x+1)(x-2)")) == structure((Symbol("x") + 1) * (Symbol("x") - 2))
    from sympy import sin, asin
    assert structure(translate_ctc_line_to_sympy(r"sin(\pi)")) == structure(sin(Symbol("pi")))
    assert structure(translate_ctc_line_to_sympy(r"2sin(\pi)").args[1]) == structure(sin(Symbol("pi")))
    assert structure(translate_ctc_line_to_sympy("arcsin(x)")) == structure(asin(Symbol("x")))
    for unsupported in (r"\begin{matrix} a & b \\ c & d \end{matrix}", r"x \in \mathbb{R}"):
        try:
            translate_ctc_line_to_sympy(unsupported)
            raise AssertionError(f"expected rejection: {unsupported!r}")
        except TranslationError:
            pass
    print("ctc_to_autosuggest_translator self-check passed")


if __name__ == "__main__":
    _self_check()
