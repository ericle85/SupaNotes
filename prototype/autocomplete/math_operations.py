from dataclasses import dataclass
from enum import Enum, auto


class MathOperation(Enum):
    # Equation solving
    SOLVE_EQUATION_ONE_STEP = auto()
    SOLVE_QUADRATIC = auto()
    SOLVE_FACTOR_FORM = auto()
    SOLVE_TRIG = auto()
    SOLVE_EXP_LOG = auto()
    SOLVE_RADICAL = auto()
    
    # Expression transforms
    SIMPLIFY_EXPRESSION = auto()
    FACTOR_EXPRESSION = auto()
    EXPAND_EXPRESSION = auto()
    CANCEL_EXPRESSION = auto()
    CONVERT_TO_DECIMAL = auto()
    EVALUATE_NUMERIC = auto()
    UNDEFINED_RESULT = auto()
    AWAITING_TRAILING_EQUALS = auto()
    
    # Calculus
    DIFFERENTIATE = auto()
    INTEGRATE = auto()
    COMPUTE_LIMIT = auto()
    EXPAND_TAYLOR = auto()
    
    # Complex numbers
    CONVERT_POLAR = auto()
    COMPUTE_MAGNITUDE = auto()
    COMPUTE_PHASE = auto()
    EULER_FORM = auto()
    
    # Linear algebra
    RREF_STEP = auto()
    COMPUTE_DETERMINANT = auto()
    COMPUTE_INVERSE = auto()
    COMPUTE_EIGENVALUES = auto()
    
    # Transforms
    LAPLACE_TRANSFORM = auto()
    INVERSE_LAPLACE = auto()
    FOURIER_TRANSFORM = auto()


@dataclass(frozen=True)
class ClassifiedIntent:
    operation: MathOperation
