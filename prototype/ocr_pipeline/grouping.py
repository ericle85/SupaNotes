"""Stroke grouping and recognizer scheduling heuristics for OCR fixtures."""

from __future__ import annotations

from typing import Any

BBox = list[float]


def stroke_times(stroke: dict[str, Any]) -> dict[str, float]:
    points = stroke.get("points", [])
    if not points:
        return {"start": 0.0, "end": 0.0}
    return {
        "start": float(points[0].get("t", 0.0)),
        "end": float(points[-1].get("t", 0.0)),
    }


def bbox_union(left: BBox | None, right: BBox | None) -> BBox | None:
    if left is None:
        return list(right) if right else None
    if right is None:
        return list(left)
    return [
        min(left[0], right[0]),
        min(left[1], right[1]),
        max(left[2], right[2]),
        max(left[3], right[3]),
    ]


def normalize_fixture(fixture: dict[str, Any]) -> dict[str, Any]:
    truth = fixture.get("truth") or {"blocks": [], "expectedMarkdown": ""}
    truth_by_stroke: dict[str, dict[str, Any]] = {}
    for block in truth.get("blocks", []):
        for stroke_id in block.get("strokes", []):
            truth_by_stroke[stroke_id] = block

    strokes_container = fixture.get("strokes", {})
    strokes = []
    for stroke in strokes_container.get("strokes", []):
        stroke_id = stroke.get("id", "")
        strokes.append(
            {
                **stroke,
                "times": stroke_times(stroke),
                "truthBlock": truth_by_stroke.get(stroke_id),
            }
        )

    canvas = strokes_container.get("canvas") or {"width": 612, "height": 792}
    return {
        **fixture,
        "strokes": {**strokes_container, "strokes": strokes},
        "truth": truth,
        "canvasInfo": canvas,
    }


UNRECOGNIZED_GROUP = {"kind": "not labeled", "content": ""}


def recognize_group(group: dict[str, Any]) -> dict[str, str]:
    """OCR pipeline seam.

    The live OCR pipeline plugs in here: given a group's strokes it must report
    what it recognized (``content``) and how it classified the line (``kind``:
    ``"math"``, ``"text"``, or ``"not labeled"``). Until the pipeline is wired
    in, every group stays unrecognized so the debugger overlay reflects reality
    instead of the fixture answer key.
    """
    return dict(UNRECOGNIZED_GROUP)


def group_completed_strokes(completed: list[dict[str, Any]]) -> list[dict[str, Any]]:
    sorted_strokes = sorted(completed, key=lambda stroke: ((stroke.get("bbox") or [0, 0, 0, 0])[1]))
    groups: list[dict[str, Any]] = []

    for stroke in sorted_strokes:
        bbox = stroke.get("bbox")
        if not bbox:
            continue

        center_y = (bbox[1] + bbox[3]) / 2
        height = max(1.0, bbox[3] - bbox[1])
        best_group: dict[str, Any] | None = None
        best_distance = float("inf")

        for group in groups:
            threshold = max(34.0, max(group["height"], height) * 1.15)
            distance = abs(center_y - group["centerY"])
            if distance < threshold and distance < best_distance:
                best_group = group
                best_distance = distance

        if best_group is None:
            groups.append(
                {
                    "strokes": [stroke],
                    "bbox": list(bbox),
                    "centerY": center_y,
                    "height": height,
                    "lastT": stroke["times"]["end"],
                }
            )
        else:
            best_group["strokes"].append(stroke)
            best_group["bbox"] = bbox_union(best_group["bbox"], bbox)
            best_group["centerY"] = (best_group["bbox"][1] + best_group["bbox"][3]) / 2
            best_group["height"] = max(1.0, best_group["bbox"][3] - best_group["bbox"][1])
            best_group["lastT"] = max(best_group["lastT"], stroke["times"]["end"])

    enriched = [{**group, **recognize_group(group)} for group in groups]
    return sorted(enriched, key=lambda group: (group["bbox"][1], group["bbox"][0]))
