"""Replay-time spatial document construction for OCR fixtures."""

from __future__ import annotations

from typing import Any

from .grouping import group_completed_strokes, normalize_fixture


def rounded_bbox(bbox: list[float]) -> list[float]:
    return [round(value, 1) for value in bbox]


def block_from_group(group: dict[str, Any], index: int, idle_seconds: float) -> dict[str, Any]:
    kind = group["kind"]
    stroke_ids = [stroke["id"] for stroke in ordered_strokes(group)]
    return {
        "id": f"block_{index + 1:03d}",
        "kind": kind,
        "bbox": rounded_bbox(group["bbox"]),
        "strokes": stroke_ids,
        "text": group["content"] if kind == "text" else "",
        "latex": group["content"] if kind == "math" else "",
        "source": "math_ctc" if kind == "math" else "apple_vision_pending",
        "recognizedAt": round(group["lastT"] + idle_seconds, 2),
    }


def group_for_client(group: dict[str, Any]) -> dict[str, Any]:
    return {
        "kind": group["kind"],
        "content": group["content"],
        "bbox": rounded_bbox(group["bbox"]),
        "lastT": round(group["lastT"], 3),
        "strokes": [stroke["id"] for stroke in ordered_strokes(group)],
    }


def ordered_strokes(group: dict[str, Any]) -> list[dict[str, Any]]:
    return sorted(group["strokes"], key=lambda stroke: (stroke["times"]["start"], stroke["id"]))


def build_final_ocr_calls(fixture: dict[str, Any], idle_seconds: float) -> list[dict[str, Any]]:
    normalized = normalize_fixture(fixture)
    groups = group_completed_strokes(normalized["strokes"].get("strokes", []))
    calls = []
    for index, group in enumerate(groups):
        calls.append(
            {
                "index": index,
                "at": round(group["lastT"] + idle_seconds, 3),
                "kind": group["kind"],
                "content": group["content"],
                "bbox": rounded_bbox(group["bbox"]),
            }
        )
    return sorted(calls, key=lambda call: call["at"])


def build_replay_state(fixture: dict[str, Any], time_seconds: float, idle_seconds: float) -> dict[str, Any]:
    normalized = normalize_fixture(fixture)
    strokes = normalized["strokes"].get("strokes", [])
    completed = [stroke for stroke in strokes if stroke["times"]["end"] <= time_seconds]
    groups = group_completed_strokes(completed)
    blocks = [
        block_from_group(group, index, idle_seconds)
        for index, group in enumerate(groups)
        if time_seconds >= group["lastT"] + idle_seconds
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
        "groups": [group_for_client(group) for group in groups],
        "blocks": blocks,
        "calls": build_final_ocr_calls(fixture, idle_seconds),
        "document": document,
    }
