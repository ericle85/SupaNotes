import os
import sys
import json

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from ocr_pipeline.recognizer import stroke_layout_features
from tests.cache_router_decodes import english_samples, math_samples, CACHE


def main():
    per_class = int(sys.argv[1]) if len(sys.argv) > 1 else 2000
    groups = [
        ("text", "train", lambda: english_samples("training", per_class)),
        ("text", "holdout", lambda: english_samples("validation", 705)),
        ("math", "train", lambda: math_samples("train", per_class)),
        ("math", "holdout", lambda: math_samples("test", 705)),
    ]

    with open(CACHE) as handle:
        rows = json.load(handle)

    cursor = 0
    for label, split, loader in groups:
        samples = loader()
        for strokes in samples:
            row = rows[cursor]
            assert row["label"] == label and row["split"] == split, (cursor, row["label"], row["split"])
            row["layout"] = stroke_layout_features(strokes)
            cursor += 1
        print(f"{label}/{split}: {len(samples)}")

    assert cursor == len(rows), (cursor, len(rows))
    with open(CACHE, "w") as handle:
        json.dump(rows, handle)
    print(f"added layout features to {len(rows)} rows")


if __name__ == "__main__":
    main()
