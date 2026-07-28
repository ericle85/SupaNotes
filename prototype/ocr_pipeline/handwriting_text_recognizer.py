"""English handwriting recognition by rasterizing strokes and running Apple Vision."""

from __future__ import annotations

import io
from functools import lru_cache
from typing import Any

RENDER_TARGET_HEIGHT_PX = 160.0
RENDER_MAX_SCALE = 6.0
RENDER_PADDING_PX = 24
RENDER_STROKE_WIDTH_PX = 3
MINIMUM_TEXT_CONFIDENCE = 0.3

EMPTY_TEXT_RESULT = {"content": "", "confidence": 0.0}


def stroke_bounds(strokes: list[list[tuple[float, float, float]]]) -> tuple[float, float, float, float]:
    xs = [point[0] for stroke in strokes for point in stroke]
    ys = [point[1] for stroke in strokes for point in stroke]
    return min(xs), min(ys), max(xs), max(ys)


def render_scale(height: float) -> float:
    if height <= 0:
        return 1.0
    return min(RENDER_MAX_SCALE, max(1.0, RENDER_TARGET_HEIGHT_PX / height))


def render_strokes_to_png(strokes: list[list[tuple[float, float, float]]]) -> bytes:
    from PIL import Image, ImageDraw

    left, top, right, bottom = stroke_bounds(strokes)
    scale = render_scale(bottom - top)
    width = int((right - left) * scale) + 2 * RENDER_PADDING_PX
    height = int((bottom - top) * scale) + 2 * RENDER_PADDING_PX
    image = Image.new("L", (max(width, 1), max(height, 1)), 255)
    canvas = ImageDraw.Draw(image)

    for stroke in strokes:
        points = [
            (
                (point[0] - left) * scale + RENDER_PADDING_PX,
                (point[1] - top) * scale + RENDER_PADDING_PX,
            )
            for point in stroke
        ]
        if len(points) < 2:
            continue
        canvas.line(points, fill=0, width=RENDER_STROKE_WIDTH_PX, joint="curve")

    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()


@lru_cache(maxsize=1)
def vision_is_available() -> bool:
    try:
        import Vision  # noqa: F401
        from Foundation import NSData  # noqa: F401
    except Exception:
        return False
    return True


def recognize_png_bytes(png_bytes: bytes) -> dict[str, Any]:
    from Foundation import NSData
    from Vision import (
        VNImageRequestHandler,
        VNRecognizeTextRequest,
        VNRequestTextRecognitionLevelAccurate,
    )

    data = NSData.dataWithBytes_length_(png_bytes, len(png_bytes))
    handler = VNImageRequestHandler.alloc().initWithData_options_(data, {})
    request = VNRecognizeTextRequest.alloc().init()
    request.setRecognitionLevel_(VNRequestTextRecognitionLevelAccurate)
    request.setUsesLanguageCorrection_(True)
    success, _ = handler.performRequests_error_([request], None)
    if not success:
        return EMPTY_TEXT_RESULT

    lines = []
    confidences = []
    for observation in request.results() or []:
        candidates = observation.topCandidates_(1)
        if not candidates:
            continue
        if candidates[0].confidence() < MINIMUM_TEXT_CONFIDENCE:
            continue
        lines.append(candidates[0].string())
        confidences.append(float(candidates[0].confidence()))
    if not lines:
        return EMPTY_TEXT_RESULT
    return {
        "content": " ".join(lines),
        "confidence": round(sum(confidences) / len(confidences), 4),
    }


def recognize_handwritten_text(
    strokes: list[list[tuple[float, float, float]]]
) -> dict[str, Any]:
    if not strokes:
        return EMPTY_TEXT_RESULT
    if not vision_is_available():
        return EMPTY_TEXT_RESULT
    try:
        return recognize_png_bytes(render_strokes_to_png(strokes))
    except Exception:
        return EMPTY_TEXT_RESULT


def _self_check() -> None:
    from pathlib import Path

    from ocr_pipeline.fixtures import load_fixture
    from ocr_pipeline.grouping import normalize_fixture, group_completed_strokes
    from ocr_pipeline.recognizer import strokes_in_writing_order

    assert vision_is_available()

    fixtures_dir = Path(__file__).resolve().parent.parent / "fixtures"
    fixture = normalize_fixture(load_fixture(fixtures_dir, "writing"))
    groups = group_completed_strokes(fixture["strokes"]["strokes"], recognize=False)
    recognized = [recognize_handwritten_text(strokes_in_writing_order(g["strokes"])) for g in groups]
    non_empty = [result for result in recognized if result["content"]]

    print("recognized:", [result["content"] for result in recognized])
    assert non_empty
    assert all(result["confidence"] > 0 for result in non_empty)
    print("handwriting_text_recognizer self-check passed")


if __name__ == "__main__":
    _self_check()
