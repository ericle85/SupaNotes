"""Replay-time spatial document construction for OCR fixtures."""

from __future__ import annotations

from typing import Any

from .grouping import gap_guides, group_completed_strokes, normalize_fixture


def autocomplete_for_latex(latex_text: str) -> dict[str, Any] | None:
    if not latex_text.strip():
        return None
    from autocomplete.autocomplete_pipeline import run_autocomplete_on_document_text

    try:
        result = run_autocomplete_on_document_text(latex_text)
    except Exception as error:
        return {"operation": "", "suggestion": "", "reason": f"pipeline error: {error}"}
    suggestion = result.suggestion
    return {
        "operation": result.classified_intent.operation.name,
        "suggestion": suggestion.suggested_text if suggestion.has_suggestion else "",
        "reason": suggestion.diagnostic_reason,
    }


def rounded_bbox(bbox: list[float]) -> list[float]:
    return [round(value, 1) for value in bbox]


def stroke_intervals(strokes: list[dict[str, Any]]) -> list[tuple[float, float]]:
    return sorted(
        (stroke["times"]["start"], stroke["times"]["end"]) for stroke in strokes
    )


def last_pen_contact_before_idle(
    last_t: float, intervals: list[tuple[float, float]], idle_seconds: float
) -> float:
    contact = last_t
    for start, end in intervals:
        if end <= last_t:
            continue
        if start - contact >= idle_seconds:
            break
        contact = end
    return contact


def block_from_group(group: dict[str, Any], index: int, fire_at: float) -> dict[str, Any]:
    kind = group["kind"]
    stroke_ids = [stroke["id"] for stroke in ordered_strokes(group)]
    latex = group["content"] if kind == "math" else ""
    return {
        "id": f"block_{index + 1:03d}",
        "kind": kind,
        "bbox": rounded_bbox(group["bbox"]),
        "strokes": stroke_ids,
        "text": group["content"] if kind == "text" else "",
        "latex": latex,
        "source": "math_ctc" if kind == "math" else "apple_vision_pending",
        "recognizedAt": round(fire_at, 2),
        "autocomplete": autocomplete_for_latex(latex),
    }


def group_for_client(group: dict[str, Any], last_contact_t: float) -> dict[str, Any]:
    return {
        "kind": group["kind"],
        "content": group["content"],
        "confidence": group.get("confidence", 0.0),
        "tokens": group.get("tokens", []),
        "bbox": rounded_bbox(group["bbox"]),
        "lastT": round(group["lastT"], 3),
        "lastPenContactT": round(last_contact_t, 3),
        "strokes": [stroke["id"] for stroke in ordered_strokes(group)],
    }


def ordered_strokes(group: dict[str, Any]) -> list[dict[str, Any]]:
    return sorted(group["strokes"], key=lambda stroke: (stroke["times"]["start"], stroke["id"]))


def build_final_ocr_calls(
    fixture: dict[str, Any], idle_seconds: float, gap_threshold: float | None = None
) -> list[dict[str, Any]]:
    normalized = normalize_fixture(fixture)
    all_strokes = normalized["strokes"].get("strokes", [])
    intervals = stroke_intervals(all_strokes)
    groups = group_completed_strokes(all_strokes, gap_threshold)
    calls = []
    for index, group in enumerate(groups):
        calls.append(
            {
                "index": index,
                "at": round(
                    last_pen_contact_before_idle(group["lastT"], intervals, idle_seconds)
                    + idle_seconds,
                    3,
                ),
                "kind": group["kind"],
                "content": group["content"],
                "bbox": rounded_bbox(group["bbox"]),
            }
        )
    return sorted(calls, key=lambda call: call["at"])


def build_replay_state(
    fixture: dict[str, Any],
    time_seconds: float,
    idle_seconds: float,
    gap_threshold: float | None = None,
) -> dict[str, Any]:
    normalized = normalize_fixture(fixture)
    strokes = normalized["strokes"].get("strokes", [])
    started = [stroke for stroke in strokes if stroke["times"]["start"] <= time_seconds]
    intervals = stroke_intervals(started)
    completed = [stroke for stroke in strokes if stroke["times"]["end"] <= time_seconds]
    groups = group_completed_strokes(completed, gap_threshold)
    contact_times = [
        last_pen_contact_before_idle(group["lastT"], intervals, idle_seconds)
        for group in groups
    ]
    blocks = [
        block_from_group(group, index, contact_t + idle_seconds)
        for index, (group, contact_t) in enumerate(zip(groups, contact_times))
        if time_seconds >= contact_t + idle_seconds
    ]

    document = {
        "pageId": normalized["name"],
        "time": round(time_seconds, 2),
        "idleTriggerSeconds": idle_seconds,
        "blocks": blocks,
        "expectedMarkdown": normalized["truth"].get("expectedMarkdown", ""),
    }
    return {
        "completedStrokeCount": len(completed),
        "totalStrokeCount": len(strokes),
        "groups": [
            group_for_client(group, contact_t)
            for group, contact_t in zip(groups, contact_times)
        ],
        "blocks": blocks,
        "calls": build_final_ocr_calls(fixture, idle_seconds, gap_threshold),
        "gapGuides": gap_guides(completed, gap_threshold),
        "document": document,
    }
