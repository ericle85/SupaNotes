"""LaTeX parser for CTC model output.

Converts LaTeX strings from the CTC model (SupaNotesML) into sympy-parseable
Python-like expressions. Maintains backward compatibility with plain text.

CTC Model Format:
  - Greek letters: \\alpha, \\beta, \\gamma
  - Fractions: \\frac{a}{b}
  - Roots: \\sqrt{x}
  - Constants: \\pi, \\infty
  - Operators: \\cdot, \\times, \\pm, \\mp
  - Brackets: \\left( ... \\right)
"""

import re
from typing import Optional


# Greek letter mapping
_GREEK_MAP = {
    'alpha': 'alpha', 'Alpha': 'Alpha',
    'beta': 'beta', 'Beta': 'Beta',
    'gamma': 'gamma', 'Gamma': 'Gamma',
    'delta': 'delta', 'Delta': 'Delta',
    'epsilon': 'epsilon', 'Epsilon': 'Epsilon',
    'zeta': 'zeta', 'Zeta': 'Zeta',
    'eta': 'eta', 'Eta': 'Eta',
    'theta': 'theta', 'Theta': 'Theta',
    'iota': 'iota', 'Iota': 'Iota',
    'kappa': 'kappa', 'Kappa': 'Kappa',
    'lambda': 'lambda', 'Lambda': 'Lambda',
    'mu': 'mu', 'Mu': 'Mu',
    'nu': 'nu', 'Nu': 'Nu',
    'xi': 'xi', 'Xi': 'Xi',
    'omicron': 'omicron', 'Omicron': 'Omicron',
    'pi': 'pi', 'Pi': 'Pi',
    'rho': 'rho', 'Rho': 'Rho',
    'sigma': 'sigma', 'Sigma': 'Sigma',
    'tau': 'tau', 'Tau': 'Tau',
    'upsilon': 'upsilon', 'Upsilon': 'Upsilon',
    'phi': 'phi', 'Phi': 'Phi',
    'chi': 'chi', 'Chi': 'Chi',
    'psi': 'psi', 'Psi': 'Psi',
    'omega': 'omega', 'Omega': 'Omega',
}

# Constants
_CONSTANTS = {
    'pi': 'pi',
    'infty': 'oo',
    'infinity': 'oo',
}

# Operators
_OPERATORS = {
    '\\cdot': '*',
    '\\times': '*',
    '\\div': '/',
    '\\pm': '\\pm',  # keep as-is, handle in sympy
    '\\mp': '\\mp',
}


def contains_latex(text: str) -> bool:
    """Check if text contains LaTeX commands."""
    return '\\frac' in text or '\\sqrt' in text or '\\left' in text or text.startswith('\\')


def parse_latex(text: str) -> str:
    """Convert LaTeX string to sympy-parseable Python expression.

    Args:
        text: LaTeX string (e.g., '\\alpha * x + \\beta = 0')

    Returns:
        Python-like expression string (e.g., 'alpha * x + beta = 0')
    """
    # Handle Python keywords that are used as math symbols
    text = text.replace('/ lambda', '/ lambda_')
    text = text.replace(' lambda ', ' lambda_ ')
    text = text.replace('lambda)', 'lambda_)')
    
    if not contains_latex(text):
        # Even non-LaTeX text might use ^ for exponents (common in math input)
        text = text.replace('^', '**')
        return text

    result = text

    # Remove \\left( and \\right) wrappers
    result = _replace_bracket_pairs(result)

    # Process \\frac{num}{den} → (num)/(den)
    result = _parse_frac(result)

    # Process \\sqrt{expr} → expr**(1/2)
    result = _parse_sqrt(result)

    # Process Greek letters
    result = _parse_greek(result)

    # Process constants
    result = _parse_constants(result)

    # Process operators
    result = _parse_operators(result)

    # Convert ^ to **
    result = result.replace('^', '**')

    # Clean up: remove braces, extra spaces
    result = result.replace('{', '').replace('}', '')
    result = _cleanup_whitespace(result)

    return result


def _replace_bracket_pairs(text: str) -> str:
    """Remove \\left( ... \\right) and similar bracket pairs."""
    patterns = [
        (r'\\left\(\\s*(.*?)\\s*\\right\)', r'(\1)'),
        (r'\\left\[\\s*(.*?)\\s*\\right\]', r'[\1]'),
        (r'\\left\{\\s*(.*?)\\s*\\right\}', r'{\1}'),
        (r'\\left\|\\s*(.*?)\\s*\\right\|', r'\1'),
    ]
    for pattern, replacement in patterns:
        text = re.sub(pattern, replacement, text)
    return text


def _parse_frac(text: str) -> str:
    """Parse \\frac{numerator}{denominator} → (numerator)/(denominator)."""
    while '\\frac{' in text:
        # Find outermost \frac{...}{...}
        match = re.search(r'\\frac\{(.+?)\}\{(.+?)\}', text)
        if not match:
            break
        num = match.group(1)
        den = match.group(2)
        replacement = f'({num})/({den})'
        text = text[:match.start()] + replacement + text[match.end():]
    return text


def _parse_sqrt(text: str) -> str:
    """Parse \\sqrt{expr} → expr**(1/2)."""
    while '\\sqrt{' in text:
        match = re.search(r'\\sqrt\{(.+?)\}', text)
        if not match:
            break
        expr = match.group(1)
        replacement = f'({expr})**(1/2)'
        text = text[:match.start()] + replacement + text[match.end():]
    return text


def _parse_greek(text: str) -> str:
    """Convert \\alpha → alpha, etc."""
    for latex_name, python_name in _GREEK_MAP.items():
        pattern = rf'\\{latex_name}'
        text = re.sub(pattern, python_name, text)
    return text


def _parse_constants(text: str) -> str:
    """Convert \\pi → pi, \\infty → oo."""
    for latex_name, python_name in _CONSTANTS.items():
        pattern = rf'\\{latex_name}'
        text = re.sub(pattern, python_name, text)
    return text


def _parse_operators(text: str) -> str:
    """Convert LaTeX operators to Python equivalents."""
    for latex_op, py_op in _OPERATORS.items():
        text = text.replace(latex_op, py_op)
    return text


def _cleanup_whitespace(text: str) -> str:
    """Normalize whitespace."""
    text = re.sub(r'\s+', ' ', text)
    return text.strip()


# Precompiled pattern for quick LaTeX detection
_LATEX_PATTERN = re.compile(r'\\[a-zA-Z]+')


def fast_detect_latex(text: str) -> bool:
    """Fast LaTeX detection using regex."""
    return bool(_LATEX_PATTERN.search(text))
