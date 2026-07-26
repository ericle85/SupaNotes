import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from ocr_pipeline.recognizer import longest_letter_run, route_kind


def test_environment_and_function_names_are_not_letter_runs():
    assert longest_letter_run(r"\begin{matrix}a\\ b\end{matrix}") == 1
    assert longest_letter_run("log_{2}n") == 1
    assert longest_letter_run("nlog_{2}n") == 4
    assert longest_letter_run(r"\frac{1}{12}") == 0
    assert longest_letter_run("hello") == 5


def test_confident_english_routes_to_text_via_letter_run():
    assert route_kind("winter,", 0.97) == "text"
    assert route_kind("x+y=2", 0.97) == "math"
    assert route_kind("anything", 0.40) == "text"


if __name__ == "__main__":
    test_environment_and_function_names_are_not_letter_runs()
    test_confident_english_routes_to_text_via_letter_run()
    print("ok")
