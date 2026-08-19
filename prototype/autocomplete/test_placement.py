import json
import os
import sys

import numpy as np

from eval_placement import (
    parse_inkml,
    compute_bbox,
    find_equal_sign_center,
    place_suggestion,
)

TOLERANCE = 0.5


def load_test_case(folder):
    strokes = parse_inkml(os.path.join(folder, "strokes.inkml"))
    with open(os.path.join(folder, "pipeline_output.json")) as f:
        pipeline = json.load(f)
    return strokes, pipeline


def test_append(strokes, pipeline):
    bbox = compute_bbox(strokes)
    placement = place_suggestion(bbox, "append")
    if placement is None:
        return False, "no placement returned"

    px, py = placement
    if px <= bbox["max_x"]:
        return False, f"x={px:.1f} not past bbox max_x={bbox['max_x']:.1f}"

    mid_y = (bbox["min_y"] + bbox["max_y"]) / 2
    if abs(py - mid_y) > TOLERANCE:
        return False, f"y={py:.1f} not centered (expected {mid_y:.1f})"

    return True, f"x={px:.1f}, y={py:.1f}"


def test_align_with_equal_sign(strokes, pipeline):
    bbox = compute_bbox(strokes)
    equal_center = find_equal_sign_center(strokes)
    if equal_center is None:
        return False, "no equal sign found in strokes"

    eq_x, eq_y = equal_center
    placement = place_suggestion(
        bbox,
        "alignWithEqualSignAbove",
        strokes=strokes,
        transcription=pipeline.get("transcription", ""),
        suggestion=pipeline.get("suggestion", ""),
    )
    if placement is None:
        return False, "no placement returned"

    px, py = placement
    if abs(px - eq_x) > TOLERANCE:
        return False, f"placement x={px:.1f} != equal sign x={eq_x:.1f}"

    return True, f"eq_center=({eq_x:.1f},{eq_y:.1f}), placement=({px:.1f},{py:.1f})"


TEST_FNS = {
    "append": test_append,
    "alignWithEqualSignAbove": test_align_with_equal_sign,
}


def run_tests(strokes_dir):
    folders = sorted(
        os.path.join(strokes_dir, d)
        for d in os.listdir(strokes_dir)
        if os.path.isdir(os.path.join(strokes_dir, d))
    )

    passed = 0
    failed = 0

    for folder in folders:
        name = os.path.basename(folder)
        strokes, pipeline = load_test_case(folder)
        mode = pipeline.get("placement", "")
        suggestion = pipeline.get("suggestion", "")

        test_fn = TEST_FNS.get(mode)
        if test_fn is None:
            print(f"  SKIP  {name} (unknown mode: {mode})")
            continue

        ok, detail = test_fn(strokes, pipeline)
        status = "PASS" if ok else "FAIL"
        if ok:
            passed += 1
        else:
            failed += 1
        print(f"  {status}  {name}  mode={mode}  suggestion='{suggestion}'  {detail}")

    print(f"\n{passed} passed, {failed} failed, {len(folders)} total")
    return failed == 0


if __name__ == "__main__":
    strokes_dir = sys.argv[1] if len(sys.argv) > 1 else "/Users/ericle/Downloads/strokes_exported"
    success = run_tests(strokes_dir)
    sys.exit(0 if success else 1)
