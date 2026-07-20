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
    try:
        from .recognizer import recognize_group as recognize_with_ctc

        return recognize_with_ctc(group)
    except Exception:
        return dict(UNRECOGNIZED_GROUP)


def build_group(strokes: list[dict[str, Any]]) -> dict[str, Any]:
    bbox = None
    last_t = 0.0
    for stroke in strokes:
        bbox = bbox_union(bbox, stroke.get("bbox"))
        last_t = max(last_t, stroke["times"]["end"])
    return {
        "strokes": strokes,
        "bbox": bbox,
        "centerY": (bbox[1] + bbox[3]) / 2,
        "height": max(1.0, bbox[3] - bbox[1]),
        "lastT": last_t,
    }


def default_gap_threshold(line: dict[str, Any]) -> float:
    return max(40.0, line["height"] * 1.2)


def split_line_into_chunks(
    line: dict[str, Any], gap_threshold: float | None = None
) -> list[dict[str, Any]]:
    strokes = [stroke for stroke in line["strokes"] if stroke.get("bbox")]
    if len(strokes) < 2:
        return [line]
    threshold = gap_threshold if gap_threshold is not None else default_gap_threshold(line)
    ordered = sorted(strokes, key=lambda stroke: stroke["bbox"][0])
    chunks = [[ordered[0]]]
    running_right = ordered[0]["bbox"][2]
    for stroke in ordered[1:]:
        if stroke["bbox"][0] - running_right > threshold:
            chunks.append([stroke])
        else:
            chunks[-1].append(stroke)
        running_right = max(running_right, stroke["bbox"][2])
    if len(chunks) == 1:
        return [line]
    return [build_group(chunk) for chunk in chunks]


def vertical_lines(completed: list[dict[str, Any]]) -> list[dict[str, Any]]:
    sorted_strokes = sorted(completed, key=lambda stroke: ((stroke.get("bbox") or [0, 0, 0, 0])[1]))
    lines: list[dict[str, Any]] = []

    for stroke in sorted_strokes:
        bbox = stroke.get("bbox")
        if not bbox:
            continue

        center_y = (bbox[1] + bbox[3]) / 2
        height = max(1.0, bbox[3] - bbox[1])
        best_line: dict[str, Any] | None = None
        best_distance = float("inf")

        for line in lines:
            threshold = max(34.0, max(line["height"], height) * 1.15)
            distance = abs(center_y - line["centerY"])
            if distance < threshold and distance < best_distance:
                best_line = line
                best_distance = distance

        if best_line is None:
            lines.append(build_group([stroke]))
        else:
            best_line["strokes"].append(stroke)
            best_line["bbox"] = bbox_union(best_line["bbox"], bbox)
            best_line["centerY"] = (best_line["bbox"][1] + best_line["bbox"][3]) / 2
            best_line["height"] = max(1.0, best_line["bbox"][3] - best_line["bbox"][1])
            best_line["lastT"] = max(best_line["lastT"], stroke["times"]["end"])

    return lines


def gap_guides(
    completed: list[dict[str, Any]], gap_threshold: float | None = None
) -> list[dict[str, Any]]:
    guides = []
    for line in vertical_lines(completed):
        strokes = sorted(
            [stroke for stroke in line["strokes"] if stroke.get("bbox")],
            key=lambda stroke: stroke["bbox"][0],
        )
        threshold = gap_threshold if gap_threshold is not None else default_gap_threshold(line)
        running_right = None
        for stroke in strokes:
            bbox = stroke["bbox"]
            if running_right is not None and bbox[0] - running_right > 0:
                gap = bbox[0] - running_right
                guides.append(
                    {
                        "x": round(bbox[0] - gap / 2, 1),
                        "y0": round(line["bbox"][1], 1),
                        "y1": round(line["bbox"][3], 1),
                        "gap": round(gap, 1),
                        "isSplit": gap > threshold,
                    }
                )
            running_right = bbox[2] if running_right is None else max(running_right, bbox[2])
    return guides


def group_completed_strokes(
    completed: list[dict[str, Any]], gap_threshold: float | None = None
) -> list[dict[str, Any]]:
    chunks: list[dict[str, Any]] = []
    for line in vertical_lines(completed):
        chunks.extend(split_line_into_chunks(line, gap_threshold))
    enriched = [{**chunk, **recognize_group(chunk)} for chunk in chunks]
    return sorted(enriched, key=lambda chunk: (chunk["bbox"][1], chunk["bbox"][0]))
