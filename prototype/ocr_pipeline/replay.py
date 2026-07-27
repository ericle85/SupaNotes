"""Replay-time spatial document construction for OCR fixtures."""

from __future__ import annotations

import json
from functools import lru_cache
from typing import Any

from .grouping import (
    gap_guides,
    group_completed_strokes,
    normalize_fixture,
    recognize_group,
)

RecognitionResult = dict[str, Any]
ERASE_EVENT_KINDS = {"eraseStroke", "eraseStrokes", "deleteStroke", "deleteStrokes"}


def autocomplete_for_latex(latex_text: str) -> dict[str, Any] | None:
    if not latex_text.strip():
        return None
    from autocomplete.autocomplete_pipeline import run_autocomplete_on_document_text

    try:
        result = run_autocomplete_on_document_text(latex_text)
    except Exception as error:
        return {"operation": "", "suggestion": "", "reason": f"pipeline error: {error}"}
    suggestion = result.suggestion
    ghost = suggestion.ghost_text
    return {
        "operation": result.classified_intent.operation.name,
        "suggestion": suggestion.suggested_text if suggestion.has_suggestion else "",
        "reason": suggestion.diagnostic_reason,
        "ghostText": (
            {"text": ghost.text, "placement": ghost.placement} if ghost else None
        ),
    }


def rounded_bbox(bbox: list[float]) -> list[float]:
    return [round(value, 1) for value in bbox]


def stroke_intervals(strokes: list[dict[str, Any]]) -> list[tuple[float, float]]:
    return sorted(
        (stroke["times"]["start"], stroke["times"]["end"]) for stroke in strokes
    )


def fixture_events(fixture: dict[str, Any]) -> list[dict[str, Any]]:
    strokes_container = fixture.get("strokes", {})
    events = []
    if isinstance(strokes_container, dict):
        events.extend(strokes_container.get("events", []))
    events.extend(fixture.get("events", []))
    return events


def event_time(event: dict[str, Any]) -> float:
    return float(event.get("at", event.get("t", event.get("time", 0.0))))


def event_kind(event: dict[str, Any]) -> str:
    return str(event.get("kind", event.get("type", event.get("action", ""))))


def event_stroke_ids(event: dict[str, Any]) -> list[str]:
    stroke_ids = event.get(
        "strokes", event.get("strokeIds", event.get("strokeIDs", []))
    )
    if isinstance(stroke_ids, str):
        return [stroke_ids]
    if not stroke_ids:
        stroke_id = event.get("strokeId", event.get("strokeID"))
        return [stroke_id] if isinstance(stroke_id, str) else []
    return [stroke_id for stroke_id in stroke_ids if isinstance(stroke_id, str)]


def erased_stroke_ids_at(events: list[dict[str, Any]], time_seconds: float) -> set[str]:
    erased: set[str] = set()
    for event in events:
        if event_time(event) > time_seconds:
            continue
        if event_kind(event) in ERASE_EVENT_KINDS:
            erased.update(event_stroke_ids(event))
    return erased


def active_strokes_at(
    strokes: list[dict[str, Any]],
    events: list[dict[str, Any]],
    time_seconds: float,
    *,
    time_key: str,
) -> list[dict[str, Any]]:
    erased = erased_stroke_ids_at(events, time_seconds)
    return [
        stroke
        for stroke in strokes
        if stroke["id"] not in erased and stroke["times"][time_key] <= time_seconds
    ]


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


def ordered_strokes(group: dict[str, Any]) -> list[dict[str, Any]]:
    return sorted(
        group["strokes"], key=lambda stroke: (stroke["times"]["start"], stroke["id"])
    )


def group_key(group: dict[str, Any]) -> tuple[str, ...]:
    return tuple(stroke["id"] for stroke in ordered_strokes(group))


@lru_cache(maxsize=1024)
def cached_recognize_group(stroke_signature: str) -> RecognitionResult:
    strokes = json.loads(stroke_signature)
    return recognize_group({"strokes": strokes})


def recognition_signature(group: dict[str, Any]) -> str:
    """Build a stable, hashable key that also carries the stroke payload.

    The replay debugger polls while playback is running. Caching by the exact
    stroke snapshot lets each synthetic OCR job run the CTC model once instead
    of re-running decode on every poll after the job has already fired.
    """

    return json.dumps(
        [
            {
                "id": stroke.get("id", ""),
                "points": stroke.get("points", []),
                "times": stroke.get("times", {}),
            }
            for stroke in ordered_strokes(group)
        ],
        sort_keys=True,
        separators=(",", ":"),
    )


def recognized_group(group: dict[str, Any]) -> dict[str, Any]:
    recognition = cached_recognize_group(recognition_signature(group))
    return {**group, **recognition}


def clear_recognition_cache() -> None:
    cached_recognize_group.cache_clear()


def block_from_group(
    group: dict[str, Any], index: int, fire_at: float
) -> dict[str, Any]:
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


def idle_fire_times(strokes: list[dict[str, Any]], idle_seconds: float) -> list[float]:
    intervals = stroke_intervals(strokes)
    fire_times = []
    for index, (_, end) in enumerate(intervals):
        next_start = intervals[index + 1][0] if index + 1 < len(intervals) else None
        if next_start is None or next_start - end >= idle_seconds:
            fire_times.append(end + idle_seconds)
    return fire_times


def ocr_call_history(
    strokes: list[dict[str, Any]],
    time_seconds: float,
    idle_seconds: float,
    gap_threshold: float | None = None,
    events: list[dict[str, Any]] | None = None,
) -> list[dict[str, Any]]:
    """Return synthetic OCR jobs that would have fired by replay time.

    Unlike the old final-call list, this never looks ahead to future strokes.
    It samples only idle pauses that have already occurred and records a new
    call when the stroke set for a grouped OCR target has changed.
    """

    calls = []
    seen_snapshots: set[tuple[str, ...]] = set()
    events = events or []
    for fire_at in idle_fire_times(strokes, idle_seconds):
        if fire_at > time_seconds:
            break
        completed_at_fire = active_strokes_at(strokes, events, fire_at, time_key="end")
        for group in group_completed_strokes(
            completed_at_fire, gap_threshold, recognize=False
        ):
            key = group_key(group)
            if key in seen_snapshots:
                continue
            seen_snapshots.add(key)
            recognized = recognized_group(group)
            calls.append(
                {
                    "index": len(calls),
                    "at": round(fire_at, 3),
                    "kind": recognized["kind"],
                    "content": recognized["content"],
                    "bbox": rounded_bbox(recognized["bbox"]),
                    "strokes": list(key),
                }
            )
    return calls


def build_replay_state(
    fixture: dict[str, Any],
    time_seconds: float,
    idle_seconds: float,
    gap_threshold: float | None = None,
) -> dict[str, Any]:
    normalized = normalize_fixture(fixture)
    strokes = normalized["strokes"].get("strokes", [])
    events = fixture_events(normalized)
    started = active_strokes_at(strokes, events, time_seconds, time_key="start")
    intervals = stroke_intervals(started)
    completed = active_strokes_at(strokes, events, time_seconds, time_key="end")
    pending_groups = group_completed_strokes(completed, gap_threshold, recognize=False)
    contact_times = [
        last_pen_contact_before_idle(group["lastT"], intervals, idle_seconds)
        for group in pending_groups
    ]

    groups = []
    block_groups = []
    for group, contact_t in zip(pending_groups, contact_times):
        if time_seconds >= contact_t + idle_seconds:
            recognized = recognized_group(group)
            groups.append(recognized)
            block_groups.append((recognized, contact_t + idle_seconds))
        else:
            groups.append(group)

    blocks = [
        block_from_group(group, index, fire_at)
        for index, (group, fire_at) in enumerate(block_groups)
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
        "calls": ocr_call_history(
            strokes, time_seconds, idle_seconds, gap_threshold, events
        ),
        "gapGuides": gap_guides(completed, gap_threshold),
        "document": document,
    }
