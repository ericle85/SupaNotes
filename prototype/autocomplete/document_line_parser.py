from dataclasses import dataclass
from typing import Union
from sympy import Expr, Symbol, Integer, Float, Rational, I, pi, E, sin, cos, tan, exp, log, sqrt
from sympy.parsing.sympy_parser import parse_expr
from autocomplete.math_engine.latex_parser import parse_latex, fast_detect_latex


@dataclass(frozen=True)
class ParsedEquation:
    left_side: Expr
    right_side: Expr
    original_text: str


@dataclass(frozen=True)
class ParsedExpression:
    expression: Expr
    original_text: str


@dataclass(frozen=True)
class UnparsableLine:
    original_text: str
    parse_error_description: str


# Greek letter names that conflict with sympy built-in functions
# (beta, gamma are sympy special functions, not symbols)
_GREEK_CONFLICT_MAP = {
    'beta': 'Beta',
    'gamma': 'Gamma',
    'Gamma': 'Gamma',
    'Beta': 'Beta',
}

def _build_greek_symbol_map():
    '''Build a map of Greek letter names to Symbol objects.'''
    from sympy import Symbol
    greek_lowercase = [
        'alpha', 'beta', 'gamma', 'delta', 'epsilon', 'zeta', 'eta',
        'theta', 'iota', 'kappa', 'lambda', 'mu', 'nu', 'xi',
        'omicron', 'pi', 'rho', 'sigma', 'tau', 'upsilon',
        'phi', 'chi', 'psi', 'omega'
    ]
    greek_uppercase = [
        'Alpha', 'Beta', 'Gamma', 'Delta', 'Epsilon', 'Zeta', 'Eta',
        'Theta', 'Iota', 'Kappa', 'Lambda', 'Mu', 'Nu', 'Xi',
        'Omicron', 'Pi', 'Rho', 'Sigma', 'Tau', 'Upsilon',
        'Phi', 'Chi', 'Psi', 'Omega'
    ]
    all_greek = greek_lowercase + greek_uppercase
    # Filter out conflicts - use unique names for conflicting ones
    unique_names = []
    for name in all_greek:
        if name.lower() in _GREEK_CONFLICT_MAP:
            # Use a unique name that won't conflict
            unique_names.append(_GREEK_CONFLICT_MAP[name])
        else:
            unique_names.append(name)
    result = {name: Symbol(name) for name in unique_names}
    # Add Symbol itself so parse_expr can use it
    # Add essential sympy types so parse_expr works
    result.update({
        'Symbol': Symbol,
        'Integer': Integer,
        'Float': Float,
        'Rational': Rational,
        'I': I,
        'pi': pi,
        'E': E,
        'e': E,  # 'e' in user input → Euler's number
        'sin': sin,
        'cos': cos,
        'tan': tan,
        'exp': exp,
        'log': log,
        'ln': log,  # 'ln' in user input → log
        'sqrt': sqrt,
        'lambda_': Symbol('lambda'),  # 'lambda' in user input → symbol
    })
    return result

GREEK_SYMBOL_MAP = _build_greek_symbol_map()



ParsedLine = Union[ParsedEquation, ParsedExpression, UnparsableLine]



def _expand_factored_form(expr_str: str) -> str:
    r"""Expand factored form like (x+1)(x-2) to x^2 - x - 2"""
    import re
    # Find patterns like (a)(b) or (a)(b) = c
    pattern = r'\(([^)]+)\)\(([^)]+)\)'
    while True:
        match = re.search(pattern, expr_str)
        if not match:
            break
        left = match.group(1)
        right = match.group(2)
        # Expand: (a)(b) = a*b
        expanded = f'({left})*({right})'
        expr_str = expr_str[:match.start()] + expanded + expr_str[match.end():]
    return expr_str

def parse_single_line(line_text: str) -> ParsedLine:
    stripped_text = line_text.strip()
    
    # Convert LaTeX input to Python-like expression (also handles ^ → ** for plain text)
    stripped_text = parse_latex(stripped_text)
    
    # Expand factored form before parsing
    stripped_text = _expand_factored_form(stripped_text)
    
    equals_sign_count = stripped_text.count("=")
    if equals_sign_count > 1:
        return UnparsableLine(
            original_text=stripped_text,
            parse_error_description="line contains multiple equals signs",
        )
    try:
        if equals_sign_count == 1:
            left_text, right_text = stripped_text.split("=")
            return ParsedEquation(
                left_side=parse_expr(left_text.strip(), global_dict=GREEK_SYMBOL_MAP),
                right_side=parse_expr(right_text.strip(), global_dict=GREEK_SYMBOL_MAP),
                original_text=stripped_text,
            )
        return ParsedExpression(
            expression=parse_expr(stripped_text, global_dict=GREEK_SYMBOL_MAP),
            original_text=stripped_text,
        )
    except Exception as parse_error:
        return UnparsableLine(
            original_text=stripped_text,
            parse_error_description=f"could not parse expression: {parse_error}",
        )
def parse_document_text(document_text: str) -> list[ParsedLine]:
    non_empty_lines = [line for line in document_text.splitlines() if line.strip()]
    return [parse_single_line(line) for line in non_empty_lines]


def read_document_lines_from_file(file_path: str) -> list[ParsedLine]:
    with open(file_path, "r") as document_file:
        return parse_document_text(document_file.read())
