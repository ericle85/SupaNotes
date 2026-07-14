import os
from dataclasses import dataclass
import pytest
from autocomplete.autocomplete_pipeline import run_autocomplete_on_document_text


@dataclass(frozen=True)
class AutocompleteCase:
    input_line: str
    expected_operation_name: str
    expected_next_line: str


def load_autocomplete_cases() -> list[AutocompleteCase]:
    cases_file_path = os.path.join(os.path.dirname(__file__), "autocomplete_cases.txt")
    with open(cases_file_path, "r") as cases_file:
        raw_lines = cases_file.read().splitlines()
    return [_parse_case_line(line) for line in raw_lines if _line_is_a_case(line)]


def _line_is_a_case(line: str) -> bool:
    stripped = line.strip()
    return bool(stripped) and not stripped.startswith("#")


def _parse_case_line(line: str) -> AutocompleteCase:
    input_part, operation_part, expected_part = (segment.strip() for segment in line.split("=>"))
    return AutocompleteCase(
        input_line=input_part,
        expected_operation_name=operation_part,
        expected_next_line=expected_part,
    )


loaded_cases = load_autocomplete_cases()


@pytest.mark.parametrize("case", loaded_cases, ids=[case.input_line for case in loaded_cases])
def test_autocomplete_case(case: AutocompleteCase):
    result = run_autocomplete_on_document_text(case.input_line)
    assert result.classified_intent.operation.name == case.expected_operation_name
    assert result.suggestion.suggested_text == case.expected_next_line
