import os
import sys
import json

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import joblib
from scipy.sparse import hstack, csr_matrix
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import cross_val_predict

from ocr_pipeline.recognizer import router_features, route_kind

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "router_decodes.json")
MODEL = os.path.join(os.path.dirname(HERE), "ocr_pipeline", "models", "router.joblib")

REGULARIZATIONS = [2.0, 5.0, 10.0]
THRESHOLDS = np.arange(0.25, 0.80, 0.025)
ANALYZERS = ["char", "char_wb"]


def load():
    with open(CACHE) as handle:
        rows = json.load(handle)
    for row in rows:
        row["numeric"] = router_features(row["content"], row["token_confidences"]) + row["layout"]
    return [row for row in rows if row["split"] == "train"], [row for row in rows if row["split"] == "holdout"]


def matrices(vectorizer, rows, fit):
    contents = [row["content"] for row in rows]
    text = vectorizer.fit_transform(contents) if fit else vectorizer.transform(contents)
    numeric = csr_matrix(np.array([row["numeric"] for row in rows]))
    labels = np.array([1 if row["label"] == "math" else 0 for row in rows])
    return hstack([text, numeric]).tocsr(), labels


def balanced(probabilities, labels, threshold):
    predicted = (probabilities >= threshold).astype(int)
    text_acc = (predicted[labels == 0] == 0).mean()
    math_acc = (predicted[labels == 1] == 1).mean()
    return (text_acc + math_acc) / 2, text_acc, math_acc


def build(analyzer, train_rows, hold_rows, norm="l2"):
    vectorizer = TfidfVectorizer(analyzer=analyzer, ngram_range=(1, 4), min_df=2, sublinear_tf=True, norm=norm)
    return vectorizer, matrices(vectorizer, train_rows, fit=True), matrices(vectorizer, hold_rows, fit=False)


def main():
    train_rows, hold_rows = load()
    print(f"train n={len(train_rows)}  holdout n={len(hold_rows)}\n")

    print("cross-validated selection on train only:")
    best = None
    for analyzer in ANALYZERS:
        vectorizer, (train_x, train_y), _ = build(analyzer, train_rows, hold_rows)
        for regularization in REGULARIZATIONS:
            estimator = LogisticRegression(max_iter=5000, C=regularization, class_weight="balanced")
            probabilities = cross_val_predict(estimator, train_x, train_y, cv=5, method="predict_proba")[:, 1]
            scored = [(balanced(probabilities, train_y, t)[0], float(t)) for t in THRESHOLDS]
            peak = max(score for score, _ in scored)
            plateau = [t for score, t in scored if score >= peak - 0.001]
            midpoint = float(np.median(plateau))
            print(
                f"  {analyzer:<8} C={regularization:<5} features {train_x.shape[1]:<6} "
                f"cv balanced {peak:.2%}  plateau {plateau[0]:.2f}-{plateau[-1]:.2f} -> {midpoint:.3f}"
            )
            candidate = (peak, analyzer, regularization, midpoint)
            best = candidate if best is None or candidate > best else best
    print(f"\nselected analyzer={best[1]} C={best[2]} threshold={best[3]:.3f} (cv balanced {best[0]:.2%})\n")

    vectorizer, (train_x, train_y), (hold_x, hold_y) = build(best[1], train_rows, hold_rows)
    model = LogisticRegression(max_iter=5000, C=best[2], class_weight="balanced").fit(train_x, train_y)
    probabilities = model.predict_proba(hold_x)[:, 1]
    holdout, text_acc, math_acc = balanced(probabilities, hold_y, best[3])
    rule = np.array([1 if route_kind(row["content"], row["confidence"]) == "math" else 0 for row in hold_rows])
    rule_balanced = ((rule[hold_y == 0] == 0).mean() + (rule[hold_y == 1] == 1).mean()) / 2

    print(f"{'rule (gate+run) holdout':>28} balanced {rule_balanced:.1%}")
    print(f"{'router holdout':>28} text {text_acc:.1%}  math {math_acc:.1%}  balanced {holdout:.1%}")

    joblib.dump({"vectorizer": vectorizer, "model": model, "threshold": best[3]}, MODEL)
    print(f"\nsaved {MODEL}")

    print("\nholdout misroutes:")
    predicted = (probabilities >= best[3]).astype(int)
    for row, guess in zip(hold_rows, predicted):
        if (guess == 1) != (row["label"] == "math"):
            print(f"  want {row['label']:>4}  conf {row['confidence']:.3f}  {row['content'][:60]!r}")


if __name__ == "__main__":
    main()
