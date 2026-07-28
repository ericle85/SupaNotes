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
    strokes_container = fixture.get("strokes", {})
    strokes = []
    for stroke in strokes_container.get("strokes", []):
        strokes.append({**stroke, "times": stroke_times(stroke)})

    canvas = strokes_container.get("canvas") or {"width": 612, "height": 792}
    return {
        **fixture,
        "strokes": {**strokes_container, "strokes": strokes},
        "canvasInfo": canvas,
    }


UNRECOGNIZED_GROUP = {"kind": "not labeled", "content": "", "confidence": 0.0, "tokens": []}


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


SPLIT_GAP_PX = 42.0


def split_line_into_chunks(line: dict[str, Any]) -> list[dict[str, Any]]:
    strokes = [stroke for stroke in line["strokes"] if stroke.get("bbox")]
    if len(strokes) < 2:
        return [line]
    threshold = SPLIT_GAP_PX
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


def group_completed_strokes(
    completed: list[dict[str, Any]],
    *,
    recognize: bool = True,
) -> list[dict[str, Any]]:
    chunks: list[dict[str, Any]] = []
    for line in vertical_lines(completed):
        chunks.extend(split_line_into_chunks(line))
    labels = (recognize_group(chunk) if recognize else dict(UNRECOGNIZED_GROUP) for chunk in chunks)
    enriched = [{**chunk, **label} for chunk, label in zip(chunks, labels)]
    return sorted(enriched, key=lambda chunk: (chunk["bbox"][1], chunk["bbox"][0]))
