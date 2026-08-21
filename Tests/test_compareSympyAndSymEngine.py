import ctypes
import subprocess
import sys
import os

BRIDGE_DIR = os.path.join(
    os.path.dirname(__file__),
    "..",
    "SupaNotesSwift",
    "SupaNotesSwift",
    "SymEngineBridge",
)
BRIDGE_CPPS = [
    os.path.join(BRIDGE_DIR, f)
    for f in [
        "SymEngineBridgeImpl.cpp",
        "LatexParsing.cpp",
        "LatexFormatting.cpp",
        "ExpressionSimplification.cpp",
    ]
]
DYLIB_PATH = "/tmp/libSymEngineBridge.dylib"

PYTHON_ENGINE_DIR = os.path.join(
    os.path.dirname(__file__),
    "..",
    "prototype",
    "autocomplete",
)

SIMPLIFY_CASES = [
    ("2+2=", "4"),
    (r"\frac{10}{2}=", "5"),
    ("3*4+1=", "13"),
    ("5(2+3)=", "25"),
    ("2(3+4)=", "14"),
    (r"\frac{6}{9}=", r"\frac{2}{3}"),
    (r"\frac{2}{3}=", "0.667"),
    (r"\frac{1}{2}=", "0.5"),
]

SOLVE_CASES = [
    ("2x=8", "x=4"),
    ("x^2=9", "x=-3, 3"),
    ("x^2+2x+1=0", "x=-1"),
    ("x^{3}=8", r"x=2, -1 - \sqrt{3} i, -1 + \sqrt{3} i"),
    ("x^{2}=16", "x=-4, 4"),
    ("x^{2}-5x+6=0", "x=2, 3"),
    ("5x^{3}=8", r"x=\frac{2 \cdot 5^{\frac{2}{3}}}{5}, \frac{5^{\frac{2}{3}} \left(-1 - \sqrt{3} i\right)}{5}, \frac{5^{\frac{2}{3}} \left(-1 + \sqrt{3} i\right)}{5}"),
    ("4x^{3}=8", r"x=\sqrt[3]{2}, \frac{\sqrt[3]{2} \left(-1 - \sqrt{3} i\right)}{2}, \frac{\sqrt[3]{2} \left(-1 + \sqrt{3} i\right)}{2}"),
]

NO_RESULT_CASES = [
    "2+x=",
    "2+2",
    "2x-8=",
    "x=2",
]


def compile_bridge():
    result = subprocess.run(
        [
            "c++", "-shared", "-fPIC", "-std=c++17",
            "-I/opt/homebrew/include",
            f"-I{BRIDGE_DIR}",
            "-L/opt/homebrew/lib", "-lsymengine", "-lflint", "-lgmp",
            "-o", DYLIB_PATH,
        ] + BRIDGE_CPPS,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(f"COMPILE FAILED:\n{result.stderr}")
        sys.exit(1)


def load_bridge():
    lib = ctypes.CDLL(DYLIB_PATH)
    lib.symengine_simplify_expression.restype = ctypes.c_char_p
    lib.symengine_simplify_expression.argtypes = [ctypes.c_char_p]
    lib.symengine_solve_equation.restype = ctypes.c_char_p
    lib.symengine_solve_equation.argtypes = [ctypes.c_char_p]
    lib.symengine_free_string.restype = None
    lib.symengine_free_string.argtypes = [ctypes.c_char_p]
    return lib


def cpp_simplify(lib, expr):
    result = lib.symengine_simplify_expression(expr.encode())
    if result is None:
        return None
    return result.decode()


def cpp_solve(lib, expr):
    result = lib.symengine_solve_equation(expr.encode())
    if result is None:
        return None
    return result.decode()


def load_python_engine():
    sys.path.insert(0, PYTHON_ENGINE_DIR)
    from math_engine.engine import do_autosuggestion
    return do_autosuggestion


def sort_solutions(s):
    if s is None:
        return None
    if "=" not in s:
        return s
    prefix, values = s.split("=", 1)
    parts = sorted(v.strip() for v in values.split(","))
    return prefix + "=" + ", ".join(parts)


def run_tests():
    compile_bridge()
    lib = load_bridge()
    do_autosuggestion = load_python_engine()

    passed = 0
    failed = 0

    def check(label, expr, actual, expected):
        nonlocal passed, failed
        if actual == expected:
            print(f"        {label:12s} {expr:30s} -> {actual}")
            passed += 1
        else:
            print(f"  FAIL  {label:12s} {expr:30s}")
            print(f"          actual:   {actual}")
            print(f"          expected: {expected}")
            failed += 1

    print("=== SIMPLIFY CASES ===")
    for expr, expected in SIMPLIFY_CASES:
        py_result, _ = do_autosuggestion(expr)
        cpp_result = cpp_simplify(lib, expr)
        check("python", expr, py_result, expected)
        check("symengine", expr, cpp_result, expected)

    print("\n=== SOLVE CASES ===")
    for expr, expected in SOLVE_CASES:
        py_result, _ = do_autosuggestion(expr)
        cpp_result = cpp_solve(lib, expr)
        check("python", expr, sort_solutions(py_result), sort_solutions(expected))
        check("symengine", expr, sort_solutions(cpp_result), sort_solutions(expected))

    print("\n=== NO-RESULT CASES ===")
    for expr in NO_RESULT_CASES:
        py_result, _ = do_autosuggestion(expr)
        cpp_solve_result = cpp_solve(lib, expr)
        cpp_simplify_result = cpp_simplify(lib, expr)
        check("python", expr, py_result, None)
        check("cpp_solve", expr, cpp_solve_result, None)
        check("cpp_simpl", expr, cpp_simplify_result, None)

    print(f"\n{'='*40}")
    print(f"PASSED: {passed}  FAILED: {failed}")
    if failed > 0:
        sys.exit(1)


if __name__ == "__main__":
    run_tests()
