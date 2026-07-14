from dataclasses import dataclass
from autocomplete.document_line_parser import read_document_lines_from_file
from autocomplete.document_context_model import build_context_for_last_line
from autocomplete.intent_classifier import classify_intent
from autocomplete.math_operations import ClassifiedIntent
from autocomplete.math_engine.engine import generate_next_line, SuggestedNextLine


@dataclass(frozen=True)
class AutocompleteResult:
    current_line_text: str
    classified_intent: ClassifiedIntent
    suggestion: SuggestedNextLine


def run_autocomplete_on_document(file_path: str) -> AutocompleteResult:
    parsed_lines = read_document_lines_from_file(file_path)
    context = build_context_for_last_line(parsed_lines)
    intent = classify_intent(context)
    suggestion = generate_next_line(context, intent)
    return AutocompleteResult(
        current_line_text=context.current_line.original_text,
        classified_intent=intent,
        suggestion=suggestion,
    )
