import re
from pathlib import Path

import pytest

from ocr_pipeline.fixtures import list_fixtures, load_fixture
from ocr_pipeline.replay import build_replay_state

FIXTURES_DIR = Path(__file__).resolve().parent.parent / "fixtures"
IDLE_SECONDS = 0.8
LATE = 10_000.0

def is_labeled(truth):
    blocks = truth.get("blocks", [])
    return bool(blocks) and all(block.get("kind") in {"text", "math"} for block in blocks)


CASES = [
    case["name"]
    for case in list_fixtures(FIXTURES_DIR)
    if is_labeled(load_fixture(FIXTURES_DIR, case["name"])["truth"])
]


def normalize_latex(latex):
    return re.sub(r"[\s{}]", "", latex)


def final_blocks(name):
    fixture = load_fixture(FIXTURES_DIR, name)
    return build_replay_state(fixture, LATE, IDLE_SECONDS)["blocks"], fixture["truth"]["blocks"]


@pytest.mark.parametrize("name", CASES)
def test_block_count_matches_truth(name):
    blocks, truth = final_blocks(name)
    assert len(blocks) == len(truth)


@pytest.mark.parametrize("name", CASES)
def test_kind_classification_matches_truth(name):
    blocks, truth = final_blocks(name)
    assert [b["kind"] for b in blocks] == [t["kind"] for t in truth]


@pytest.mark.parametrize("name", CASES)
def test_blocks_ordered_top_to_bottom(name):
    blocks, _ = final_blocks(name)
    tops = [b["bbox"][1] for b in blocks]
    assert tops == sorted(tops)


@pytest.mark.parametrize("name", CASES)
def test_math_blocks_are_recognized(name):
    blocks, _ = final_blocks(name)
    for block in blocks:
        if block["kind"] == "math":
            assert block["latex"].strip()
            assert block["source"] == "math_ctc"


def test_incremental_build_only_shows_completed_lines():
    two_line = "case_20260718_220526"
    fixture = load_fixture(FIXTURES_DIR, two_line)
    strokes = sorted(
        fixture["strokes"]["strokes"], key=lambda s: s["points"][-1]["t"]
    )
    midpoint = strokes[len(strokes) // 2 - 1]["points"][-1]["t"] + IDLE_SECONDS / 2
    early = build_replay_state(fixture, midpoint, IDLE_SECONDS)
    assert len(early["blocks"]) < 2


def test_math_latex_accuracy_across_fixtures():
    total = matched = 0
    misses = []
    for name in CASES:
        blocks, truth = final_blocks(name)
        truth_by_kind = [t for t in truth if t["kind"] == "math"]
        math_blocks = [b for b in blocks if b["kind"] == "math"]
        for block, expected in zip(math_blocks, truth_by_kind):
            total += 1
            if normalize_latex(block["latex"]) == normalize_latex(expected["latex"]):
                matched += 1
            else:
                misses.append(f"{name}: got {block['latex']!r} want {expected['latex']!r}")
    print(f"\nmath latex exact: {matched}/{total}")
    for miss in misses:
        print("  miss:", miss)
    assert matched / total >= 0.6
