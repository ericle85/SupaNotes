from dataclasses import dataclass
from autocomplete.document_line_parser import ParsedLine


@dataclass(frozen=True)
class DocumentContext:
    current_line: ParsedLine
    preceding_lines: list[ParsedLine]


def build_context_for_last_line(parsed_lines: list[ParsedLine]) -> DocumentContext:
    return DocumentContext(
        current_line=parsed_lines[-1],
        preceding_lines=parsed_lines[:-1],
    )


def build_context_at_index(parsed_lines: list[ParsedLine], line_index: int) -> DocumentContext:
    return DocumentContext(
        current_line=parsed_lines[line_index],
        preceding_lines=parsed_lines[:line_index],
    )
