from dataclasses import dataclass
from autocomplete.document_context_model import DocumentContext
from autocomplete.document_line_parser import ParsedEquation, UnparsableLine
from autocomplete.math_operations import ClassifiedIntent, MathOperation
from autocomplete.math_engine.equation_solving import (
    generate_next_solving_step,
    equation_contains_solvable_variable,
)
from autocomplete.math_engine.expression_transforms import simplify_expression, factor_expression


@dataclass(frozen=True)
class SuggestedNextLine:
    suggested_text: str
    diagnostic_reason: str = ""

    @property
    def has_suggestion(self) -> bool:
        return self.diagnostic_reason == ""


def generate_next_line(context: DocumentContext, intent: ClassifiedIntent) -> SuggestedNextLine:
    current_line = context.current_line
    if isinstance(current_line, UnparsableLine):
        return SuggestedNextLine("", current_line.parse_error_description)
    if intent.operation == MathOperation.SOLVE_EQUATION_ONE_STEP:
        return _suggest_equation_step(current_line)
    if intent.operation == MathOperation.SIMPLIFY_EXPRESSION:
        return SuggestedNextLine(simplify_expression(current_line))
    if intent.operation == MathOperation.FACTOR_EXPRESSION:
        return SuggestedNextLine(factor_expression(current_line))
    return SuggestedNextLine("", "no operation matched the current line")


def _suggest_equation_step(line: ParsedEquation) -> SuggestedNextLine:
    if not equation_contains_solvable_variable(line):
        return SuggestedNextLine("", "equation has no variable to solve for")
    return SuggestedNextLine(generate_next_solving_step(line).resulting_equation_text)
