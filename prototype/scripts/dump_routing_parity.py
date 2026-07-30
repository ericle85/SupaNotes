import os
import sys
import json

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from ocr_pipeline.fixtures import load_fixture
from ocr_pipeline.grouping import group_completed_strokes, normalize_fixture
from ocr_pipeline.recognizer import (
    decode,
    load_recognizer,
    point_sequences_from_strokes,
    route_group,
    route_kind,
    router_features,
    stroke_layout_features,
    looks_like_drawing,
)

from pathlib import Path
FIXTURES_DIR = Path(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))) / "fixtures"
OUTPUT = FIXTURES_DIR / "routing_parity.json"


def main():
    model, vocab = load_recognizer()
    fixture_names = [
        name for name in os.listdir(FIXTURES_DIR)
        if (FIXTURES_DIR / name).is_dir()
        and (FIXTURES_DIR / name / "strokes.json").exists()
    ]
    fixture_names.sort()
    results = []

    for name in fixture_names:
        fixture = load_fixture(FIXTURES_DIR, name)
        normalized = normalize_fixture(fixture)
        all_strokes = normalized["strokes"]["strokes"]
        groups = group_completed_strokes(all_strokes, recognize=False)

        for i, group in enumerate(groups):
            strokes = point_sequences_from_strokes(group["strokes"])
            if not strokes:
                continue
            if looks_like_drawing(strokes):
                continue

            ctc = decode(model, vocab, strokes)
            content = ctc["content"]
            confidence = ctc["confidence"]
            token_confidences = [t["confidence"] for t in ctc["tokens"]]

            kind_heuristic = route_kind(content, confidence)
            kind_ml = route_group(content, token_confidences, strokes)

            features_numeric = router_features(content, token_confidences)
            features_layout = stroke_layout_features(strokes)

            results.append({
                "fixture": name,
                "group_index": i,
                "content": content,
                "confidence": confidence,
                "token_confidences": token_confidences,
                "route_heuristic": kind_heuristic,
                "route_ml": kind_ml,
                "features_numeric": features_numeric,
                "features_layout": features_layout,
                "strokes": [
                    [{"x": p[0], "y": p[1], "t": p[2]} for p in stroke]
                    for stroke in strokes
                ],
            })

    with open(OUTPUT, "w") as f:
        json.dump(results, f, indent=2)
    print(f"Wrote {len(results)} groups to {OUTPUT}")
    for r in results:
        flag = " <-- DIFFERS" if r["route_heuristic"] != r["route_ml"] else ""
        print(f"  {r['fixture']} group {r['group_index']}: content='{r['content']}' heuristic={r['route_heuristic']} ml={r['route_ml']}{flag}")


if __name__ == "__main__":
    main()
