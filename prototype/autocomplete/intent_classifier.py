from sympy import Add
from autocomplete.document_context_model import DocumentContext
from autocomplete.document_line_parser import ParsedEquation, ParsedExpression
from autocomplete.math_operations import ClassifiedIntent, MathOperation


def classify_intent(context: DocumentContext) -> ClassifiedIntent:
    current_line = context.current_line
    if isinstance(current_line, ParsedEquation):
        return ClassifiedIntent(operation=MathOperation.SOLVE_EQUATION_ONE_STEP)
    if isinstance(current_line, ParsedExpression):
        if _expression_contains_power_term(current_line):
            return ClassifiedIntent(operation=MathOperation.FACTOR_EXPRESSION)
        return ClassifiedIntent(operation=MathOperation.SIMPLIFY_EXPRESSION)
    return ClassifiedIntent(operation=MathOperation.SIMPLIFY_EXPRESSION)


def _expression_contains_power_term(line: ParsedExpression) -> bool:
    return any(term.is_Pow for term in _iterate_addition_terms(line.expression))


def _iterate_addition_terms(expression):
    if isinstance(expression, Add):
        return expression.args
    return (expression,)
