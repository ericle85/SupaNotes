import subprocess
import sys
import os
import tempfile
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

from compareSympyAndSymEngine import (
    SIMPLIFY_CASES, SOLVE_CASES, NO_RESULT_CASES,
    compile_bridge, load_bridge, load_python_engine,
    cpp_simplify, cpp_solve, sort_solutions,
)

IMGCAT = "/Applications/iTerm.app/Contents/Resources/utilities/imgcat"


def render_row(status, label, expr, latex_str, color="white"):
    fig, ax = plt.subplots(figsize=(14, 0.7))
    ax.axis('off')
    fig.patch.set_alpha(0)

    status_color = "lime" if status == "PASS" else "red"
    header = f"{status}  {label:12s}  "
    ax.text(
        0.01, 0.5,
        header,
        fontsize=14,
        color=status_color,
        family='monospace',
        verticalalignment='center',
        horizontalalignment='left',
        transform=ax.transAxes,
    )

    if expr:
        ax.text(
            0.20, 0.5,
            f"${expr}$",
            fontsize=18,
            color="cyan",
            verticalalignment='center',
            horizontalalignment='left',
            transform=ax.transAxes,
        )

    if latex_str is not None:
        ax.text(
            0.45, 0.5,
            f"${latex_str}$",
            fontsize=18,
            color=color,
            verticalalignment='center',
            horizontalalignment='left',
            transform=ax.transAxes,
        )
    else:
        ax.text(
            0.45, 0.5,
            "None",
            fontsize=14,
            color="gray",
            family='monospace',
            verticalalignment='center',
            horizontalalignment='left',
            transform=ax.transAxes,
        )

    with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as f:
        path = f.name
    fig.savefig(path, bbox_inches='tight', transparent=True, dpi=120, pad_inches=0.1)
    plt.close(fig)
    subprocess.run([IMGCAT, path])
    os.unlink(path)


def check_and_render(label, expr, actual, expected, results):
    match = (actual == expected)
    if match:
        render_row("PASS", label, expr, actual, color="white")
        results["passed"] += 1
    else:
        render_row("FAIL", label, expr, actual, color="red")
        render_row("    ", "  expected", "", expected, color="lime")
        results["failed"] += 1


def run_tests():
    compile_bridge()
    lib = load_bridge()
    do_autosuggestion = load_python_engine()

    results = {"passed": 0, "failed": 0}

    print("=== SIMPLIFY CASES ===")
    for expr, expected in SIMPLIFY_CASES:
        py_result, _ = do_autosuggestion(expr)
        cpp_result = cpp_simplify(lib, expr)
        check_and_render("python", expr, py_result, expected, results)
        check_and_render("symengine", expr, cpp_result, expected, results)

    print("\n=== SOLVE CASES ===")
    for expr, expected in SOLVE_CASES:
        py_result, _ = do_autosuggestion(expr)
        cpp_result = cpp_solve(lib, expr)
        check_and_render("python", expr, sort_solutions(py_result), sort_solutions(expected), results)
        check_and_render("symengine", expr, sort_solutions(cpp_result), sort_solutions(expected), results)

    print("\n=== NO-RESULT CASES ===")
    for expr in NO_RESULT_CASES:
        py_result, _ = do_autosuggestion(expr)
        cpp_solve_result = cpp_solve(lib, expr)
        cpp_simplify_result = cpp_simplify(lib, expr)
        check_and_render("python", expr, py_result, None, results)
        check_and_render("cpp_solve", expr, cpp_solve_result, None, results)
        check_and_render("cpp_simpl", expr, cpp_simplify_result, None, results)

    print(f"\n{'='*40}")
    print(f"PASSED: {results['passed']}  FAILED: {results['failed']}")
    if results["failed"] > 0:
        sys.exit(1)


if __name__ == "__main__":
    run_tests()
