import os
from dataclasses import dataclass
import pytest
from autocomplete.autocomplete_pipeline import run_autocomplete_on_document_text


NO_SUGGESTION_SENTINEL = "NO_SUGGESTION"
EXPECTED_FAILURE_MARKER = "xfail:"


@dataclass(frozen=True)
class AutocompleteCase:
    input_line: str
    expected_operation_name: str
    expected_next_line: str
    is_expected_failure: bool


def load_autocomplete_cases() -> list[AutocompleteCase]:
    cases_file_path = os.path.join(os.path.dirname(__file__), "autocomplete_cases.txt")
    with open(cases_file_path, "r") as cases_file:
        raw_lines = cases_file.read().splitlines()
    return [_parse_case_line(line) for line in raw_lines if _line_is_a_case(line)]


def _line_is_a_case(line: str) -> bool:
    stripped = line.strip()
    return bool(stripped) and not stripped.startswith("#")


def _parse_case_line(line: str) -> AutocompleteCase:
    working_text = line.strip()
    is_expected_failure = working_text.startswith(EXPECTED_FAILURE_MARKER)
    if is_expected_failure:
        working_text = working_text[len(EXPECTED_FAILURE_MARKER):].strip()
    input_part, operation_part, expected_part = (segment.strip() for segment in working_text.split("=>"))
    return AutocompleteCase(
        input_line=input_part,
        expected_operation_name=operation_part,
        expected_next_line=expected_part,
        is_expected_failure=is_expected_failure,
    )


def _build_parametrize_entry(case: AutocompleteCase):
    marks = [pytest.mark.xfail(reason="known limitation", strict=True)] if case.is_expected_failure else []
    return pytest.param(case, id=case.input_line, marks=marks)


loaded_cases = load_autocomplete_cases()


@pytest.mark.parametrize("case", [_build_parametrize_entry(case) for case in loaded_cases])
def test_autocomplete_case(case: AutocompleteCase):
    result = run_autocomplete_on_document_text(case.input_line)
    if case.expected_next_line == NO_SUGGESTION_SENTINEL:
        assert result.suggestion.has_suggestion is False
        assert result.suggestion.diagnostic_reason != ""
        if case.expected_operation_name != NO_SUGGESTION_SENTINEL:
            assert result.operation == case.expected_operation_name.lower()
        return
    assert result.suggestion.has_suggestion is True
    assert result.operation == case.expected_operation_name.lower()
    assert result.suggestion.suggested_text == case.expected_next_line
