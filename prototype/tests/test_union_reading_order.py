from ocr_pipeline.grouping import group_completed_strokes
from ocr_pipeline.replay import log_entry, union_stroke_ids


def stroke(stroke_id: str, left: float, start: float) -> dict:
    return {
        "id": stroke_id,
        "bbox": [left, 0.0, left + 10.0, 30.0],
        "times": {"start": start, "end": start + 0.5},
        "points": [
            {"x": left, "y": 0.0, "t": start},
            {"x": left + 10.0, "y": 30.0, "t": start + 0.5},
        ],
    }


def block(bbox_left: float, strokes: list[dict]) -> dict:
    rights = [item["bbox"][2] for item in strokes]
    return {
        "bbox": [bbox_left, 0.0, max(rights), 30.0],
        "strokeIds": [item["id"] for item in strokes],
    }


def test_prepended_digit_leads_the_union():
    written_first = [
        stroke("s1", 60.0, 0.0),
        stroke("s2", 80.0, 1.0),
        stroke("s3", 100.0, 2.0),
    ]
    prepended = [stroke("s4", 0.0, 9.0)]

    stroke_ids = union_stroke_ids(block(0.0, prepended), [block(60.0, written_first)])

    assert stroke_ids == ["s4", "s1", "s2", "s3"]


def test_union_is_ordered_ids_only():
    written_first = [stroke("s1", 60.0, 0.0), stroke("s2", 80.0, 1.0)]
    prepended = [stroke("s3", 0.0, 9.0)]
    stroke_ids = union_stroke_ids(block(0.0, prepended), [block(60.0, written_first)])

    assert stroke_ids == ["s3", "s1", "s2"]


def test_grouping_hands_back_strokes_in_time_order():
    out_of_order = [
        stroke("late_left", 0.0, 5.0),
        stroke("early_right", 20.0, 1.0),
    ]

    groups = group_completed_strokes(out_of_order, recognize=False)

    assert [item["id"] for item in groups[0]["strokes"]] == ["early_right", "late_left"]


def test_stacked_strokes_keep_writing_order_inside_a_block():
    fraction_bar = stroke("bar", 0.0, 1.0)
    numerator = stroke("num", 5.0, 0.0)
    denominator = stroke("den", 5.0, 2.0)
    ordered_by_time = [numerator, fraction_bar, denominator]

    stroke_ids = union_stroke_ids(block(0.0, ordered_by_time), [])

    assert stroke_ids == ["num", "bar", "den"]


def test_already_merged_neighbour_keeps_its_reading_order():
    merged = block(
        0.0,
        [stroke("late_left", 0.0, 9.0), stroke("early_right", 20.0, 1.0)],
    )
    appended = block(60.0, [stroke("newest", 60.0, 12.0)])

    stroke_ids = union_stroke_ids(appended, [merged])

    assert stroke_ids == ["late_left", "early_right", "newest"]


def test_log_entry_stores_ordered_stroke_ids_not_strokes():
    group = {
        "kind": "math",
        "content": "x",
        "confidence": 1.0,
        "tokens": [],
        "bbox": [0.0, 0.0, 10.0, 10.0],
        "centerY": 5.0,
        "height": 10.0,
        "lastT": 1.5,
        "strokes": [stroke("s1", 0.0, 0.0), stroke("s2", 10.0, 1.0)],
    }

    entry = log_entry(group, 0, 2.0, [])

    assert entry["strokeIds"] == ["s1", "s2"]
    assert "strokes" not in entry
