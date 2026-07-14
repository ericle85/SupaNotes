from dataclasses import dataclass
from autocomplete.document_context_model import DocumentContext
from autocomplete.math_operations import ClassifiedIntent, MathOperation
from autocomplete.math_engine.equation_solving import generate_next_solving_step
from autocomplete.math_engine.expression_transforms import simplify_expression, factor_expression


@dataclass(frozen=True)
class SuggestedNextLine:
    suggested_text: str


def generate_next_line(context: DocumentContext, intent: ClassifiedIntent) -> SuggestedNextLine:
    if intent.operation == MathOperation.SOLVE_EQUATION_ONE_STEP:
        return SuggestedNextLine(generate_next_solving_step(context.current_line).resulting_equation_text)
    if intent.operation == MathOperation.SIMPLIFY_EXPRESSION:
        return SuggestedNextLine(simplify_expression(context.current_line))
    if intent.operation == MathOperation.FACTOR_EXPRESSION:
        return SuggestedNextLine(factor_expression(context.current_line))
    return SuggestedNextLine("")
