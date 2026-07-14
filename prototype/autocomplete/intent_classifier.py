from sympy import Add, Symbol, sin, cos, tan, exp, log, sqrt, I, Matrix, E, S
from autocomplete.document_context_model import DocumentContext
from autocomplete.document_line_parser import ParsedEquation, ParsedExpression, UnparsableLine
from autocomplete.math_operations import ClassifiedIntent, MathOperation

# Variables that indicate the user is solving for them (single unknown)
_SINGLE_VAR_INDICATORS = ("x", "y", "z", "t", "w")


def classify_intent(context: DocumentContext) -> ClassifiedIntent:
    current_line = context.current_line

    if isinstance(current_line, UnparsableLine):
        return ClassifiedIntent(operation=MathOperation.SIMPLIFY_EXPRESSION)

    if isinstance(current_line, ParsedEquation):
        return _classify_equation(current_line, context)
    if isinstance(current_line, ParsedExpression):
        return _classify_expression(current_line, context)

    return ClassifiedIntent(operation=MathOperation.SIMPLIFY_EXPRESSION)


def _has_single_unknown(line: ParsedEquation) -> bool:
    """Check if equation has exactly one variable that's a common solving variable.
    Physics equations like F=ma have multiple variables and should not be 'solved'."""
    all_symbols = line.left_side.free_symbols | line.right_side.free_symbols
    if len(all_symbols) <= 1:
        return True
    names = {s.name for s in all_symbols}
    # Check for Greek letters or underscore variables (physics notation)
    has_greek_or_underscore = any(
        len(n) > 1 and n[0].islower() and n.isalpha()
        for n in names
    )
    if has_greek_or_underscore:
        return False  # Multi-variable physics equation, don't solve
    # Check for common solving variables
    x_names = {s.name for s in all_symbols if s.name == 'x'}
    if x_names:
        return True
    known_names = {s.name for s in all_symbols}
    for indicator in _SINGLE_VAR_INDICATORS:
        if indicator in known_names:
            return True
    return False


def _classify_equation(line: ParsedEquation, context: DocumentContext) -> ClassifiedIntent:
    left = line.left_side
    right = line.right_side
    all_symbols = line.left_side.free_symbols | line.right_side.free_symbols

    # Check for factored form: (x+a)(x+b) = 0
    if right == 0 and left.is_Mul:
        binomials = [f for f in left.args if f.is_Add or (f.is_Mul and len(f.free_symbols) > 0)]
        if len(binomials) >= 2:
            return ClassifiedIntent(operation=MathOperation.SOLVE_FACTOR_FORM)

    # Only classify as equation to solve if there's a single unknown
    # (physics equations like F=ma should just be simplified)
    if not _has_single_unknown(line):
        return ClassifiedIntent(operation=MathOperation.SIMPLIFY_EXPRESSION)

    # Check for trigonometric equations
    if _contains_trig(left) or _contains_trig(right):
        return ClassifiedIntent(operation=MathOperation.SOLVE_TRIG)

    # Check for exponential equations
    if _contains_exp(left) or _contains_exp(right):
        return ClassifiedIntent(operation=MathOperation.SOLVE_EXP_LOG)

    # Check for logarithmic equations
    if _contains_log(left) or _contains_log(right):
        return ClassifiedIntent(operation=MathOperation.SOLVE_EXP_LOG)

    # Check for radical equations
    if _contains_sqrt(left) or _contains_sqrt(right):
        return ClassifiedIntent(operation=MathOperation.SOLVE_RADICAL)

    # Check for quadratic equations
    if _is_quadratic(left, all_symbols):
        return ClassifiedIntent(operation=MathOperation.SOLVE_QUADRATIC)

    # Default: standard equation solving
    return ClassifiedIntent(operation=MathOperation.SOLVE_EQUATION_ONE_STEP)


def _classify_expression(line: ParsedExpression, context: DocumentContext) -> ClassifiedIntent:
    expr = line.expression

    # Check for complex numbers (contains imaginary unit I)
    if I in expr.atoms():
        return ClassifiedIntent(operation=MathOperation.CONVERT_POLAR)

    # Check for expandable expressions FIRST (e.g., (x+1)**2)
    if _needs_expansion(expr):
        return ClassifiedIntent(operation=MathOperation.EXPAND_EXPRESSION)

    # Check if expression has power terms (for factoring)
    if _expression_contains_power_term(line):
        return ClassifiedIntent(operation=MathOperation.FACTOR_EXPRESSION)

    # Check for cancellation opportunities
    if _needs_cancellation(expr):
        return ClassifiedIntent(operation=MathOperation.CANCEL_EXPRESSION)

    # Default: simplify
    return ClassifiedIntent(operation=MathOperation.SIMPLIFY_EXPRESSION)


def _contains_trig(expr):
    """Check if expression contains trigonometric functions"""
    trig_funcs = (sin, cos, tan)
    if hasattr(expr, "func") and expr.func in trig_funcs:
        return True
    return any(
        hasattr(a, "func") and a.func in trig_funcs for a in expr.atoms()
    ) if hasattr(expr, "atoms") else False


def _contains_exp(expr):
    """Check if expression contains exponential functions (exp() or e**x)"""
    exp_funcs = (exp,)
    if hasattr(expr, "func") and expr.func in exp_funcs:
        return True
    if expr.is_Pow and expr.base == E:
        return True
    if hasattr(expr, "atoms"):
        for a in expr.atoms():
            if hasattr(a, "func") and a.func in exp_funcs:
                return True
    return False


def _contains_log(expr):
    """Check if expression contains logarithmic functions"""
    log_funcs = (log,)
    if hasattr(expr, "func") and expr.func in log_funcs:
        return True
    return any(
        hasattr(a, "func") and a.func in log_funcs for a in expr.atoms()
    ) if hasattr(expr, "atoms") else False


def _contains_sqrt(expr):
    """Check if expression contains square root (sqrt(x) is Pow(x, S.Half))"""
    if expr.is_Pow and expr.exp == S.Half:
        return True
    if hasattr(expr, "func") and expr.func == sqrt:
        return True
    if hasattr(expr, "atoms"):
        for a in expr.atoms():
            if a.is_Pow and a.exp == S.Half:
                return True
    return False


def _is_quadratic(expr, symbols):
    """Check if expression is a quadratic in one of the symbols"""
    for sym in symbols:
        degree = expr.as_poly(sym).degree() if expr.as_poly(sym) else -1
        if degree == 2:
            return True
    return False


def _needs_expansion(expr):
    """Check if expression needs expansion (e.g., (x+1)**2)"""
    # Check if expression itself is a power with integer exponent > 1
    if expr.is_Pow and expr.exp.is_integer and expr.exp > 1:
        return True
    # Check atoms for power terms
    return any(
        arg.is_Pow and arg.exp.is_integer and arg.exp > 1
        for arg in expr.atoms()
    ) if hasattr(expr, "atoms") else False


def _needs_cancellation(expr):
    """Check if expression has common factors that can be cancelled
    Only for complex expressions (fractions, roots), not simple sums."""
    if expr.is_Mul:
        for arg in expr.args:
            if arg.is_Pow and arg.exp.is_Rational:
                return True
    return False


def _expression_contains_power_term(line: ParsedExpression) -> bool:
    expr = line.expression
    if isinstance(expr, Add):
        terms = expr.args
    else:
        terms = (expr,)
    return any(term.is_Pow for term in terms)
