import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from ocr_pipeline.recognizer import longest_letter_run, route_kind, route_group, stroke_layout_features


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


def horizontal_word(count):
    return [[(x + offset, 0.0, 0.0), (x + offset + 0.8, 1.0, 1.0)] for offset, x in enumerate(range(count))]


def test_layout_features_are_finite_and_degrade_safely():
    assert stroke_layout_features([]) == [0.0] * 8
    features = stroke_layout_features(horizontal_word(5))
    assert len(features) == 8 and all(value == value for value in features)


def test_route_group_returns_a_kind():
    assert route_group("x^{2}+y^{2}=z^{2}", [0.99] * 9, horizontal_word(9)) in {"math", "text"}
    assert route_group("", [], []) in {"math", "text"}


if __name__ == "__main__":
    test_environment_and_function_names_are_not_letter_runs()
    test_confident_english_routes_to_text_via_letter_run()
    test_layout_features_are_finite_and_degrade_safely()
    test_route_group_returns_a_kind()
    print("ok")
