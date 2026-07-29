"""English handwriting recognition by sending raw strokes to Google's online ink recognizer."""

from __future__ import annotations

import json
import urllib.error
import urllib.request
from typing import Any

GOOGLE_INK_ENDPOINT = "https://inputtools.google.com/request?itc=en-t-i0-handwrit&app=supanotes"
REQUEST_TIMEOUT_SECONDS = 6.0
SUCCESS_STATUS = "SUCCESS"

# ponytail: the endpoint returns candidates ranked but unscored, so a recognized
# result gets a flat confidence. Swap in a real score if Google ever exposes one.
RECOGNIZED_CONFIDENCE = 1.0

EMPTY_TEXT_RESULT = {"content": "", "confidence": 0.0}


def stroke_as_ink_arrays(stroke: list[tuple[float, float, float]]) -> list[list[Any]]:
    xs = [round(point[0], 2) for point in stroke]
    ys = [round(point[1], 2) for point in stroke]
    ts = [int(point[2] * 1000) for point in stroke]
    return [xs, ys, ts]


def writing_area(strokes: list[list[tuple[float, float, float]]]) -> dict[str, float]:
    xs = [point[0] for stroke in strokes for point in stroke]
    ys = [point[1] for stroke in strokes for point in stroke]
    return {
        "writing_area_width": round(max(xs) - min(xs), 2),
        "writing_area_height": round(max(ys) - min(ys), 2),
    }


def recognition_request_body(strokes: list[list[tuple[float, float, float]]]) -> bytes:
    payload = {
        "options": "enable_pre_space",
        "requests": [
            {
                "writing_guide": writing_area(strokes),
                "ink": [stroke_as_ink_arrays(stroke) for stroke in strokes],
                "language": "en",
            }
        ],
    }
    return json.dumps(payload).encode("utf-8")


def post_recognition_request(body: bytes) -> Any:
    request = urllib.request.Request(
        GOOGLE_INK_ENDPOINT,
        data=body,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
        return json.loads(response.read().decode("utf-8"))


def top_candidate(payload: Any) -> str:
    if not isinstance(payload, list) or not payload:
        return ""
    if payload[0] != SUCCESS_STATUS:
        return ""
    if len(payload) < 2 or not payload[1]:
        return ""
    candidates = payload[1][0][1]
    if not candidates:
        return ""
    return candidates[0]


def recognize_handwritten_text_with_google_ink(
    strokes: list[list[tuple[float, float, float]]]
) -> dict[str, Any]:
    if not strokes:
        return EMPTY_TEXT_RESULT
    try:
        payload = post_recognition_request(recognition_request_body(strokes))
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError):
        return EMPTY_TEXT_RESULT
    content = top_candidate(payload)
    if not content:
        return EMPTY_TEXT_RESULT
    return {"content": content, "confidence": RECOGNIZED_CONFIDENCE}


def _self_check() -> None:
    from pathlib import Path

    from ocr_pipeline.fixtures import load_fixture
    from ocr_pipeline.grouping import group_completed_strokes, normalize_fixture
    from ocr_pipeline.recognizer import point_sequences_from_strokes

    fixtures_dir = Path(__file__).resolve().parent.parent / "fixtures"
    fixture = normalize_fixture(load_fixture(fixtures_dir, "writing"))
    groups = group_completed_strokes(fixture["strokes"]["strokes"], recognize=False)
    recognized = [
        recognize_handwritten_text_with_google_ink(point_sequences_from_strokes(group["strokes"]))
        for group in groups
    ]

    print("recognized:", [result["content"] for result in recognized])
    assert any(result["content"] for result in recognized)
    print("google_ink_handwriting_recognizer self-check passed")


if __name__ == "__main__":
    _self_check()
