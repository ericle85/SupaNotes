import os
import sys
import glob
import json
import contextlib
import io

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import torch

from ctc.preprocessing import parse_inkml
from ocr_pipeline.recognizer import load_recognizer, decode

DEEPWRITING = "/Volumes/Games/deepwriting/deepwriting_{}.npz"
MATHWRITING = "/Volumes/Games/mathwriting/mathwriting-2024/{}"
CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "router_decodes.json")


def deepwriting_strokes(sample, std, mean):
    xy = np.cumsum(np.column_stack([sample[:, 0] * std[0] + mean[0], sample[:, 1] * std[1] + mean[1]]), axis=0)
    pen = sample[:, 2]
    strokes = []
    start = 0
    for i in range(len(sample)):
        if pen[i] == 1 or i == len(sample) - 1:
            seg = xy[start:i + 1]
            if len(seg) >= 2:
                strokes.append(np.column_stack([seg, np.arange(len(seg), dtype=np.float64)]))
            start = i + 1
    return strokes


def english_samples(split, limit):
    data = np.load(DEEPWRITING.format(split), allow_pickle=True)
    std, mean = data["std"], data["mean"]
    return [deepwriting_strokes(s, std, mean) for s in data["strokes"][:limit]]


def math_samples(split, limit):
    files = sorted(glob.glob(os.path.join(MATHWRITING.format(split), "*.inkml")))[:limit]
    return [strokes for strokes in (parse_inkml(f)[0] for f in files) if strokes]


def decode_all(model, vocab, samples, label, split):
    rows = []
    for index, strokes in enumerate(samples):
        if index % 200 == 0:
            print(f"  {label}/{split} {index}/{len(samples)}", flush=True)
        with contextlib.redirect_stdout(io.StringIO()):
            result = decode(model, vocab, strokes)
        rows.append(
            {
                "label": label,
                "split": split,
                "content": result["content"],
                "confidence": result["confidence"],
                "token_confidences": [token["confidence"] for token in result["tokens"]],
                "tokens": [token["token"] for token in result["tokens"]],
            }
        )
    return rows


def main():
    per_class = int(sys.argv[1]) if len(sys.argv) > 1 else 2000
    torch.set_num_threads(max(1, os.cpu_count() - 2))
    with contextlib.redirect_stdout(io.StringIO()):
        model, vocab = load_recognizer()

    rows = []
    rows += decode_all(model, vocab, english_samples("training", per_class), "text", "train")
    rows += decode_all(model, vocab, english_samples("validation", 705), "text", "holdout")
    rows += decode_all(model, vocab, math_samples("train", per_class), "math", "train")
    rows += decode_all(model, vocab, math_samples("test", 705), "math", "holdout")

    with open(CACHE, "w") as handle:
        json.dump(rows, handle)
    print(f"wrote {len(rows)} rows to {CACHE}")


if __name__ == "__main__":
    main()
