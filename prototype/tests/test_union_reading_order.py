from ocr_pipeline.replay import union_of_strokes


def stroke(stroke_id: str, left: float, start: float) -> dict:
    return {
        "id": stroke_id,
        "bbox": [left, 0.0, left + 10.0, 30.0],
        "times": {"start": start, "end": start + 0.5},
        "points": [{"x": left, "y": 0.0, "t": start}, {"x": left + 10.0, "y": 30.0, "t": start + 0.5}],
    }


def block(bbox_left: float, strokes: list[dict]) -> dict:
    rights = [item["bbox"][2] for item in strokes]
    return {"bbox": [bbox_left, 0.0, max(rights), 30.0], "strokes": strokes}


def test_prepended_digit_leads_the_union():
    written_first = [stroke("s1", 60.0, 0.0), stroke("s2", 80.0, 1.0), stroke("s3", 100.0, 2.0)]
    prepended = [stroke("s4", 0.0, 9.0)]

    union = union_of_strokes(block(0.0, prepended), [block(60.0, written_first)], {
        item["id"]: item for item in written_first + prepended
    })

    assert [item["id"] for item in union] == ["s4", "s1", "s2", "s3"]


def test_restamped_times_ascend_so_the_recognizer_keeps_the_order():
    written_first = [stroke("s1", 60.0, 0.0), stroke("s2", 80.0, 1.0)]
    prepended = [stroke("s3", 0.0, 9.0)]
    lookup = {item["id"]: item for item in written_first + prepended}

    union = union_of_strokes(block(0.0, prepended), [block(60.0, written_first)], lookup)
    starts = [item["times"]["start"] for item in union]

    assert starts == sorted(starts)
    assert starts == [0.0, 1.0, 9.0]
    assert [point["t"] for point in union[0]["points"]] == [0.0, 0.5]


def test_stacked_strokes_keep_their_writing_order_inside_a_block():
    fraction_bar = stroke("bar", 0.0, 1.0)
    numerator = stroke("num", 5.0, 0.0)
    denominator = stroke("den", 5.0, 2.0)
    strokes = [fraction_bar, numerator, denominator]
    lookup = {item["id"]: item for item in strokes}

    union = union_of_strokes(block(0.0, strokes), [], lookup)

    assert [item["id"] for item in union] == ["num", "bar", "den"]


def test_stroke_durations_survive_the_shift():
    strokes = [stroke("s1", 60.0, 0.0), stroke("s2", 0.0, 5.0)]
    lookup = {item["id"]: item for item in strokes}

    union = union_of_strokes(block(0.0, [strokes[1]]), [block(60.0, [strokes[0]])], lookup)

    for item in union:
        assert item["times"]["end"] - item["times"]["start"] == 0.5
