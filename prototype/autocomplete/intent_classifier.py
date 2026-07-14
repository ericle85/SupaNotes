from autocomplete.document_context_model import DocumentContext
from autocomplete.document_line_parser import ParsedEquation, ParsedExpression, UnparsableLine
from autocomplete.math_operations import ClassifiedIntent, MathOperation


def classify_intent(context: DocumentContext) -> ClassifiedIntent:
    line = context.current_line
    if isinstance(line, ParsedEquation):
        return ClassifiedIntent(operation=MathOperation.SOLVE_EQUATION_ONE_STEP)
    if isinstance(line, ParsedExpression):
        return ClassifiedIntent(operation=MathOperation.SIMPLIFY_EXPRESSION)
    return ClassifiedIntent(operation=MathOperation.SIMPLIFY_EXPRESSION)
