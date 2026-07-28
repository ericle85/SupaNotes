"""Append-only log of recognized writing, newest last, corrections as supersessions."""

from __future__ import annotations

from typing import Any

from .latex_validation import latex_parses

BBox = list[float]

MERGE_HORIZONTAL_GAP_RATIO = 1.0
MERGE_VERTICAL_OVERLAP_RATIO = 0.4


def bbox_height(bbox: BBox) -> float:
    return max(1.0, bbox[3] - bbox[1])


def vertical_overlap(left: BBox, right: BBox) -> float:
    return min(left[3], right[3]) - max(left[1], right[1])


def horizontal_gap(left: BBox, right: BBox) -> float:
    return max(left[0], right[0]) - min(left[2], right[2])


def boxes_should_merge(left: BBox, right: BBox) -> bool:
    if left is None or right is None:
        return False
    shorter_height = min(bbox_height(left), bbox_height(right))
    if vertical_overlap(left, right) < MERGE_VERTICAL_OVERLAP_RATIO * shorter_height:
        return False
    taller_height = max(bbox_height(left), bbox_height(right))
    return horizontal_gap(left, right) <= MERGE_HORIZONTAL_GAP_RATIO * taller_height


def superseded_entry_ids(log: list[dict[str, Any]]) -> set[str]:
    superseded: set[str] = set()
    for entry in log:
        superseded.update(entry.get("supersedes", []))
    return superseded


def live_entries(log: list[dict[str, Any]]) -> list[dict[str, Any]]:
    superseded = superseded_entry_ids(log)
    return [entry for entry in log if entry["id"] not in superseded]


def entry_stroke_ids(entry: dict[str, Any]) -> list[str]:
    return [stroke["id"] for stroke in entry["strokes"]]


def logged_stroke_ids(log: list[dict[str, Any]]) -> set[str]:
    stroke_ids: set[str] = set()
    for entry in live_entries(log):
        stroke_ids.update(entry_stroke_ids(entry))
    return stroke_ids


def entries_to_merge_with(
    log: list[dict[str, Any]],
    bbox: BBox,
    active_stroke_ids: set[str],
) -> list[dict[str, Any]]:
    candidates = []
    for entry in live_entries(log):
        if entry["kind"] == "ink":
            continue
        if not set(entry_stroke_ids(entry)).issubset(active_stroke_ids):
            continue
        if boxes_should_merge(entry["bbox"], bbox):
            candidates.append(entry)
    return candidates


def merge_is_allowed(merged_kind: str, merged_content: str, part_contents: list[str]) -> bool:
    if merged_kind == "ink":
        return False
    if merged_kind != "math":
        return True
    if latex_parses(merged_content):
        return True
    parts_that_parsed = [content for content in part_contents if latex_parses(content)]
    return not parts_that_parsed


def _self_check() -> None:
    same_line_left = [0.0, 100.0, 50.0, 130.0]
    same_line_right = [58.0, 100.0, 110.0, 130.0]
    far_right = [400.0, 100.0, 450.0, 130.0]
    line_below = [0.0, 200.0, 50.0, 230.0]
    written_over = [40.0, 102.0, 70.0, 128.0]

    assert boxes_should_merge(same_line_left, same_line_right)
    assert boxes_should_merge(same_line_left, written_over)
    assert not boxes_should_merge(same_line_left, far_right)
    assert not boxes_should_merge(same_line_left, line_below)

    log = [
        {"id": "entry_001", "kind": "math", "bbox": same_line_left, "supersedes": [],
         "strokes": [{"id": "s1"}]},
        {"id": "entry_002", "kind": "math", "bbox": same_line_right, "supersedes": [],
         "strokes": [{"id": "s2"}]},
    ]
    assert [entry["id"] for entry in live_entries(log)] == ["entry_001", "entry_002"]

    merged = log + [
        {"id": "entry_003", "kind": "math", "bbox": same_line_left, "supersedes": ["entry_001", "entry_002"],
         "strokes": [{"id": "s1"}, {"id": "s2"}]}
    ]
    assert [entry["id"] for entry in live_entries(merged)] == ["entry_003"]
    assert logged_stroke_ids(merged) == {"s1", "s2"}

    assert [entry["id"] for entry in entries_to_merge_with(log, written_over, {"s1", "s2"})] == [
        "entry_001",
        "entry_002",
    ]
    assert [entry["id"] for entry in entries_to_merge_with(log, written_over, {"s2"})] == ["entry_002"]
    assert entries_to_merge_with(log, line_below, {"s1", "s2"}) == []
    assert entries_to_merge_with(log, far_right, {"s1", "s2"}) == []

    assert merge_is_allowed("math", "2x + 3 = 7", ["2x + 3", "= 7"])
    assert merge_is_allowed("math", "2+3= 5", ["2+3=", "5"])
    assert not merge_is_allowed("math", "2x = 4 = 9", ["2x = 4", "9"])
    assert not merge_is_allowed("math", r"2x=4 \begin{matrix}", ["2x=4", "x"])
    assert merge_is_allowed("math", "?? ??", ["??", "??"])
    assert merge_is_allowed("text", "hello world", ["hello", "world"])
    assert not merge_is_allowed("ink", "", [""])
    print("recognition_log self-check passed")


if __name__ == "__main__":
    _self_check()
