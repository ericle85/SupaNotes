import os
import sys
import json
import math

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import joblib

from ocr_pipeline.recognizer import ROUTER_PATH, router_features, stroke_layout_features

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "router_decodes.json")
EXPORT = os.path.join(os.path.dirname(HERE), "ocr_pipeline", "models", "router_weights.json")


def character_ngrams(content, low, high):
    for word in content.lower().split():
        padded = f" {word} "
        for size in range(low, high + 1):
            yield padded[:size]
            offset = 0
            while offset + size < len(padded):
                offset += 1
                yield padded[offset : offset + size]
            if offset == 0:
                break


def swift_style_score(export, content, numeric):
    counts = {}
    for gram in character_ngrams(content, export["ngram_min"], export["ngram_max"]):
        entry = export["vocabulary"].get(gram)
        if entry is not None:
            counts[gram] = counts.get(gram, 0) + 1
    values = {gram: (1.0 + math.log(count)) * export["vocabulary"][gram][0] for gram, count in counts.items()}
    norm = math.sqrt(sum(value * value for value in values.values())) or 1.0
    total = export["bias"]
    total += sum(value / norm * export["vocabulary"][gram][1] for gram, value in values.items())
    total += sum(value * weight for value, weight in zip(numeric, export["numeric_weights"]))
    return 1.0 / (1.0 + math.exp(-total))


def main():
    router = joblib.load(ROUTER_PATH)
    vectorizer, model = router["vectorizer"], router["model"]
    weights = model.coef_[0]
    names = vectorizer.get_feature_names_out()
    idf = vectorizer.idf_

    export = {
        "analyzer": vectorizer.analyzer,
        "ngram_min": vectorizer.ngram_range[0],
        "ngram_max": vectorizer.ngram_range[1],
        "lowercase": vectorizer.lowercase,
        "sublinear_tf": vectorizer.sublinear_tf,
        "norm": vectorizer.norm,
        "threshold": router["threshold"],
        "bias": float(model.intercept_[0]),
        "vocabulary": {
            str(name): [round(float(idf[index]), 6), round(float(weights[index]), 6)]
            for index, name in enumerate(names)
        },
        "numeric_weights": [round(float(w), 6) for w in weights[len(names) :]],
    }

    with open(EXPORT, "w") as handle:
        json.dump(export, handle)
    size = os.path.getsize(EXPORT) / 1e6
    print(f"wrote {EXPORT} ({size:.2f} MB, {len(export['vocabulary'])} n-grams, {len(export['numeric_weights'])} numeric)")

    with open(CACHE) as handle:
        rows = [row for row in json.load(handle) if row["split"] == "holdout"]

    from scipy.sparse import csr_matrix, hstack

    numerics = [router_features(row["content"], row["token_confidences"]) + row["layout"] for row in rows]
    features = hstack([vectorizer.transform([row["content"] for row in rows]), csr_matrix(np.array(numerics))]).tocsr()
    reference = model.predict_proba(features)[:, 1]
    ported = np.array([swift_style_score(export, row["content"], numeric) for row, numeric in zip(rows, numerics)])

    print(f"parity vs sklearn: max abs prob diff {np.abs(reference - ported).max():.2e}")
    disagreements = ((reference >= export["threshold"]) != (ported >= export["threshold"])).sum()
    print(f"routing disagreements: {disagreements}/{len(rows)}")
    assert disagreements == 0, "ported scorer disagrees with sklearn"


if __name__ == "__main__":
    main()
