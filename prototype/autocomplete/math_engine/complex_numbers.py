from sympy import Abs, arg, re, im, I, exp, simplify, expand_complex, N
from autocomplete.document_line_parser import ParsedExpression


def convert_rectangular_to_polar(line: ParsedExpression) -> str:
    magnitude = _compute_magnitude_value(line.expression)
    phase_angle_in_radians = _compute_phase_angle_in_radians(line.expression)
    return _format_polar_form(magnitude, phase_angle_in_radians)


def convert_polar_to_rectangular(line: ParsedExpression) -> str:
    return str(_expand_to_rectangular_form(line.expression))


def compute_magnitude(line: ParsedExpression) -> str:
    return str(_compute_magnitude_value(line.expression))


def compute_phase_angle(line: ParsedExpression) -> str:
    return f"{_compute_phase_angle_in_radians(line.expression)} rad"


def express_in_euler_form(line: ParsedExpression) -> str:
    magnitude = _compute_magnitude_value(line.expression)
    phase_angle_in_radians = _compute_phase_angle_in_radians(line.expression)
    return f"{magnitude}*exp(I*{phase_angle_in_radians})"


def _compute_magnitude_value(expression):
    return simplify(Abs(expression))


def _compute_phase_angle_in_radians(expression):
    return N(arg(expression))


def _expand_to_rectangular_form(expression):
    rectangular_expression = expand_complex(expression)
    real_part = simplify(re(rectangular_expression))
    imaginary_part = simplify(im(rectangular_expression))
    return real_part + imaginary_part * I


def _format_polar_form(magnitude, phase_angle_in_radians) -> str:
    return f"{magnitude} ∠ {phase_angle_in_radians} rad"
