from dataclasses import dataclass
from typing import Union
from sympy import Expr
from sympy.core.relational import Relational
from autocomplete.ctc_to_autosuggest_translator import (
    translate_ctc_line_to_sympy,
    TranslationError,
)


@dataclass(frozen=True)
class ParsedEquation:
    left_side: Expr
    right_side: Expr
    original_text: str


@dataclass(frozen=True)
class ParsedExpression:
    expression: Expr
    original_text: str


@dataclass(frozen=True)
class UnparsableLine:
    original_text: str
    parse_error_description: str


ParsedLine = Union[ParsedEquation, ParsedExpression, UnparsableLine]


def parse_single_line(line_text: str) -> ParsedLine:
    stripped_text = line_text.strip()
    try:
        translated = translate_ctc_line_to_sympy(stripped_text)
    except TranslationError as translation_error:
        return UnparsableLine(
            original_text=stripped_text,
            parse_error_description=str(translation_error),
        )
    if isinstance(translated, Relational):
        return ParsedEquation(
            left_side=translated.lhs,
            right_side=translated.rhs,
            original_text=stripped_text,
        )
    return ParsedExpression(expression=translated, original_text=stripped_text)


def parse_document_text(document_text: str) -> list[ParsedLine]:
    non_empty_lines = [line for line in document_text.splitlines() if line.strip()]
    return [parse_single_line(line) for line in non_empty_lines]


def read_document_lines_from_file(file_path: str) -> list[ParsedLine]:
    with open(file_path, "r") as document_file:
        return parse_document_text(document_file.read())
