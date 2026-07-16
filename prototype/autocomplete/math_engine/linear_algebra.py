from dataclasses import dataclass
from typing import Optional
from sympy import Matrix
from autocomplete.document_line_parser import ParsedExpression
from autocomplete.math_engine.latex_format import to_latex


@dataclass(frozen=True)
class RowReductionStep:
    resulting_matrix_text: str
    move_description: str
    is_fully_reduced: bool


def generate_next_rref_step(line: ParsedExpression) -> RowReductionStep:
    matrix = line.expression
    row_count = matrix.rows
    column_count = matrix.cols
    pivot_row_index = 0
    for column_index in range(column_count):
        if pivot_row_index >= row_count:
            break
        nonzero_rows_at_or_below_pivot = [
            row_index
            for row_index in range(pivot_row_index, row_count)
            if matrix[row_index, column_index] != 0
        ]
        if not nonzero_rows_at_or_below_pivot:
            continue
        step = _next_move_for_pivot_column(
            matrix, pivot_row_index, column_index, nonzero_rows_at_or_below_pivot
        )
        if step is not None:
            return step
        pivot_row_index += 1
    return RowReductionStep(
        resulting_matrix_text=_format_matrix(matrix),
        move_description="already in reduced row echelon form",
        is_fully_reduced=True,
    )


def _next_move_for_pivot_column(
    matrix: Matrix,
    pivot_row_index: int,
    column_index: int,
    nonzero_rows_at_or_below_pivot: list[int],
) -> Optional[RowReductionStep]:
    pivot_entry = matrix[pivot_row_index, column_index]
    if pivot_entry == 0:
        source_row_index = nonzero_rows_at_or_below_pivot[0]
        swapped_matrix = _apply_row_swap(matrix, pivot_row_index, source_row_index)
        return RowReductionStep(
            resulting_matrix_text=_format_matrix(swapped_matrix),
            move_description=(
                f"swap row {pivot_row_index + 1} with row {source_row_index + 1}"
            ),
            is_fully_reduced=False,
        )
    if pivot_entry != 1:
        normalized_matrix = _apply_row_scale(matrix, pivot_row_index, pivot_entry)
        return RowReductionStep(
            resulting_matrix_text=_format_matrix(normalized_matrix),
            move_description=f"divide row {pivot_row_index + 1} by {pivot_entry}",
            is_fully_reduced=False,
        )
    rows_needing_elimination = [
        row_index
        for row_index in range(matrix.rows)
        if row_index != pivot_row_index and matrix[row_index, column_index] != 0
    ]
    if rows_needing_elimination:
        target_row_index = rows_needing_elimination[0]
        multiplier = matrix[target_row_index, column_index]
        eliminated_matrix = _apply_row_elimination(
            matrix, target_row_index, pivot_row_index, multiplier
        )
        return RowReductionStep(
            resulting_matrix_text=_format_matrix(eliminated_matrix),
            move_description=(
                f"subtract {multiplier} times row {pivot_row_index + 1} "
                f"from row {target_row_index + 1}"
            ),
            is_fully_reduced=False,
        )
    return None


def _apply_row_swap(matrix: Matrix, first_row_index: int, second_row_index: int) -> Matrix:
    rows = [list(matrix.row(row_index)) for row_index in range(matrix.rows)]
    rows[first_row_index], rows[second_row_index] = (
        rows[second_row_index],
        rows[first_row_index],
    )
    return Matrix(rows)


def _apply_row_scale(matrix: Matrix, row_index: int, divisor) -> Matrix:
    rows = [list(matrix.row(index)) for index in range(matrix.rows)]
    rows[row_index] = [entry / divisor for entry in rows[row_index]]
    return Matrix(rows)


def _apply_row_elimination(
    matrix: Matrix, target_row_index: int, pivot_row_index: int, multiplier
) -> Matrix:
    rows = [list(matrix.row(index)) for index in range(matrix.rows)]
    pivot_row = rows[pivot_row_index]
    rows[target_row_index] = [
        target_entry - multiplier * pivot_entry
        for target_entry, pivot_entry in zip(rows[target_row_index], pivot_row)
    ]
    return Matrix(rows)


def _format_matrix(matrix: Matrix) -> str:
    return to_latex(matrix)


def compute_determinant(line: ParsedExpression) -> str:
    return to_latex(line.expression.det())


def compute_inverse_matrix(line: ParsedExpression) -> str:
    return to_latex(line.expression.inv())


def compute_eigenvalues(line: ParsedExpression) -> str:
    eigenvalue_to_multiplicity = line.expression.eigenvals()
    eigenvalues_in_stable_order = sorted(eigenvalue_to_multiplicity, key=str)
    eigenvalues_repeated_by_multiplicity = [
        to_latex(eigenvalue)
        for eigenvalue in eigenvalues_in_stable_order
        for _ in range(eigenvalue_to_multiplicity[eigenvalue])
    ]
    return ", ".join(eigenvalues_repeated_by_multiplicity)
