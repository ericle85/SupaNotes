from dataclasses import dataclass
from typing import Union
from sympy import Expr
from sympy.parsing.sympy_parser import parse_expr


@dataclass(frozen=True)
class ParsedEquation:
    left_side: Expr
    right_side: Expr
    original_text: str


@dataclass(frozen=True)
class ParsedExpression:
    expression: Expr
    original_text: str


ParsedLine = Union[ParsedEquation, ParsedExpression]


def parse_single_line(line_text: str) -> ParsedLine:
    stripped_text = line_text.strip()
    if "=" in stripped_text:
        left_text, right_text = stripped_text.split("=", 1)
        return ParsedEquation(
            left_side=parse_expr(left_text.strip()),
            right_side=parse_expr(right_text.strip()),
            original_text=stripped_text,
        )
    return ParsedExpression(
        expression=parse_expr(stripped_text),
        original_text=stripped_text,
    )


def parse_document_text(document_text: str) -> list[ParsedLine]:
    non_empty_lines = [line for line in document_text.splitlines() if line.strip()]
    return [parse_single_line(line) for line in non_empty_lines]


def read_document_lines_from_file(file_path: str) -> list[ParsedLine]:
    with open(file_path, "r") as document_file:
        return parse_document_text(document_file.read())
