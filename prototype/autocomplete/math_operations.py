from dataclasses import dataclass
from enum import Enum, auto


class MathOperation(Enum):
    SOLVE_EQUATION_ONE_STEP = auto()
    SIMPLIFY_EXPRESSION = auto()
    FACTOR_EXPRESSION = auto()


@dataclass(frozen=True)
class ClassifiedIntent:
    operation: MathOperation
