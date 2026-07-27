from copy import deepcopy
import re
from pathlib import Path

import pytest

from ocr_pipeline.fixtures import list_fixtures, load_fixture
from ocr_pipeline.replay import build_replay_state

FIXTURES_DIR = Path(__file__).resolve().parent.parent / "fixtures"
IDLE_SECONDS = 0.8
LATE = 10_000.0
SPATIAL_MUTATION_CASE = "case_20260721_012208"
SPATIAL_MUTATION_LATEX = [
    "3+2=",
    "3+2+5=",
    r"\frac{6}{2}=",
    r"\frac{6(3)}{2}+5=",
    "160-2=",
]


def is_labeled(truth):
    blocks = truth.get("blocks", [])
    return bool(blocks) and all(
        block.get("kind") in {"text", "math"} for block in blocks
    )


CASES = [
    case["name"]
    for case in list_fixtures(FIXTURES_DIR)
    if is_labeled(load_fixture(FIXTURES_DIR, case["name"])["truth"])
]


def normalize_latex(latex):
    return re.sub(r"[\s{}]", "", latex)


def final_blocks(name):
    fixture = load_fixture(FIXTURES_DIR, name)
    return (
        build_replay_state(fixture, LATE, IDLE_SECONDS)["blocks"],
        fixture["truth"]["blocks"],
    )


def block_latex(blocks):
    return [block["latex"] for block in blocks]


def stroke_ids(blocks):
    return [stroke_id for block in blocks for stroke_id in block["strokes"]]


def fixture_with_strokes(fixture, strokes, events=None):
    copy = deepcopy(fixture)
    copy["strokes"]["strokes"] = strokes
    if events is not None:
        copy["events"] = events
    return copy


def translated_strokes(strokes, *, dx, dy, id_prefix, start_time):
    first_time = min(point["t"] for stroke in strokes for point in stroke["points"])
    copies = []
    for index, stroke in enumerate(strokes, start=1):
        translated = deepcopy(stroke)
        translated["id"] = f"{id_prefix}_{index:04d}"
        translated["bbox"] = [
            stroke["bbox"][0] + dx,
            stroke["bbox"][1] + dy,
            stroke["bbox"][2] + dx,
            stroke["bbox"][3] + dy,
        ]
        for point in translated["points"]:
            point["x"] += dx
            point["y"] += dy
            point["t"] = start_time + (point["t"] - first_time)
        copies.append(translated)
    return copies


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
    two_line = next(
        (
            name
            for name in CASES
            if len(load_fixture(FIXTURES_DIR, name)["truth"].get("blocks", [])) >= 2
        ),
        None,
    )
    if two_line is None:
        pytest.skip("no labeled multi-line fixture available")
    fixture = load_fixture(FIXTURES_DIR, two_line)
    strokes = sorted(fixture["strokes"]["strokes"], key=lambda s: s["points"][-1]["t"])
    midpoint = strokes[len(strokes) // 2 - 1]["points"][-1]["t"] + IDLE_SECONDS / 2
    early = build_replay_state(fixture, midpoint, IDLE_SECONDS)
    assert len(early["blocks"]) < len(fixture["truth"]["blocks"])


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
                misses.append(
                    f"{name}: got {block['latex']!r} want {expected['latex']!r}"
                )
    print(f"\nmath latex exact: {matched}/{total}")
    for miss in misses:
        print("  miss:", miss)
    if total == 0:
        pytest.skip("no labeled math blocks available")
    assert matched / total >= 0.6


def test_erasing_ocrd_ink_higher_on_page_removes_only_that_spatial_block():
    fixture = load_fixture(FIXTURES_DIR, SPATIAL_MUTATION_CASE)
    original_blocks = build_replay_state(fixture, LATE, IDLE_SECONDS)["blocks"]
    assert block_latex(original_blocks) == SPATIAL_MUTATION_LATEX

    erased_strokes = original_blocks[0]["strokes"]
    erased_fixture = fixture_with_strokes(
        fixture,
        fixture["strokes"]["strokes"],
        events=[{"kind": "eraseStrokes", "at": 20.0, "strokes": erased_strokes}],
    )
    erased_blocks = build_replay_state(erased_fixture, LATE, IDLE_SECONDS)["blocks"]

    assert block_latex(erased_blocks) == SPATIAL_MUTATION_LATEX[1:]
    assert not set(erased_strokes).intersection(stroke_ids(erased_blocks))
    assert [block["bbox"] for block in erased_blocks] == [
        block["bbox"] for block in original_blocks[1:]
    ]


def test_move_and_copy_paste_preserve_ocr_and_update_spatial_geometry():
    fixture = load_fixture(FIXTURES_DIR, SPATIAL_MUTATION_CASE)
    source_strokes = fixture["strokes"]["strokes"][:6]
    source_fixture = fixture_with_strokes(fixture, source_strokes)
    source_block = build_replay_state(source_fixture, LATE, IDLE_SECONDS)["blocks"][0]
    assert source_block["latex"] == "3+2="

    dx = 260.0
    dy = 160.0
    pasted_strokes = translated_strokes(
        source_strokes,
        dx=dx,
        dy=dy,
        id_prefix="pasted_stroke",
        start_time=4.0,
    )
    copied_fixture = fixture_with_strokes(fixture, source_strokes + pasted_strokes)
    copied_blocks = build_replay_state(copied_fixture, LATE, IDLE_SECONDS)["blocks"]

    assert block_latex(copied_blocks) == ["3+2=", "3+2="]
    assert copied_blocks[0]["bbox"] == source_block["bbox"]
    expected_bbox = []
    for value, shift in zip(source_block["bbox"], [dx, dy, dx, dy]):
        expected_bbox.append(value + shift)

    assert copied_blocks[1]["bbox"] == expected_bbox

    moved_fixture = fixture_with_strokes(
        fixture,
        source_strokes + pasted_strokes,
        events=[
            {
                "kind": "eraseStrokes",
                "at": 3.2,
                "strokes": [stroke["id"] for stroke in source_strokes],
            }
        ],
    )
    moved_blocks = build_replay_state(moved_fixture, LATE, IDLE_SECONDS)["blocks"]

    assert block_latex(moved_blocks) == ["3+2="]
    assert moved_blocks[0]["bbox"] == copied_blocks[1]["bbox"]
    assert all(
        stroke_id.startswith("pasted_stroke_")
        for stroke_id in moved_blocks[0]["strokes"]
    )
