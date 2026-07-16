from dataclasses import dataclass
from autocomplete.document_line_parser import parse_document_text
from autocomplete.document_context_model import build_context_for_last_line
from autocomplete.intent_classifier import classify_intent
from autocomplete.math_operations import ClassifiedIntent
from autocomplete.math_engine.engine import generate_next_line, SuggestedNextLine


@dataclass(frozen=True)
class AutocompleteResult:
    current_line_text: str
    classified_intent: ClassifiedIntent
    suggestion: SuggestedNextLine


def run_autocomplete_on_document_text(document_text: str) -> AutocompleteResult:
    parsed_lines = parse_document_text(document_text)
    context = build_context_for_last_line(parsed_lines)
    intent = classify_intent(context) # TODO
    suggestion = generate_next_line(context, intent)
    return AutocompleteResult(
        current_line_text=context.current_line.original_text,
        classified_intent=ClassifiedIntent(operation=suggestion.operation),
        suggestion=suggestion,
    )


def run_autocomplete_on_document(file_path: str) -> AutocompleteResult:
    with open(file_path, "r") as document_file:
        return run_autocomplete_on_document_text(document_file.read())
