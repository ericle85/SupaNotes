import os
import sys
import glob
import contextlib
import io
import re

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import torch

from ctc.preprocessing import parse_inkml
from ocr_pipeline.recognizer import (
    load_recognizer,
    decode,
    classify_kind,
    route_kind,
    longest_letter_run,
    MATH_CONFIDENCE_GATE,
    LETTER_RUN_GATE,
)

DEEPWRITING = "/Volumes/Games/deepwriting/deepwriting_validation.npz"
MATHWRITING = "/Volumes/Games/mathwriting/mathwriting-2024/test"


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


def english_samples():
    data = np.load(DEEPWRITING, allow_pickle=True)
    std, mean = data["std"], data["mean"]
    return [deepwriting_strokes(s, std, mean) for s in data["strokes"]]


def math_samples(limit):
    files = sorted(glob.glob(os.path.join(MATHWRITING, "*.inkml")))[:limit]
    return [strokes for strokes in (parse_inkml(f)[0] for f in files) if strokes]


def decode_all(model, vocab, samples):
    rows = []
    for strokes in samples:
        with contextlib.redirect_stdout(io.StringIO()):
            result = decode(model, vocab, strokes)
        rows.append(result)
    return rows


def gate_only(row, gate, run_gate):
    return "text" if row["confidence"] < gate else classify_kind(row["content"])


def run_only(row, gate, run_gate):
    return "text" if longest_letter_run(row["content"]) >= run_gate else classify_kind(row["content"])


def gate_or_run(row, gate, run_gate):
    if row["confidence"] < gate or longest_letter_run(row["content"]) >= run_gate:
        return "text"
    return classify_kind(row["content"])


def accuracy(rule, english, math, gate, run_gate):
    text_acc = np.mean([rule(row, gate, run_gate) == "text" for row in english])
    math_acc = np.mean([rule(row, gate, run_gate) == "math" for row in math])
    return text_acc, math_acc, (text_acc + math_acc) / 2


def main():
    limit = int(sys.argv[1]) if len(sys.argv) > 1 else 705
    torch.set_num_threads(max(1, os.cpu_count() - 2))

    with contextlib.redirect_stdout(io.StringIO()):
        model, vocab = load_recognizer()

    english = decode_all(model, vocab, english_samples())
    math = decode_all(model, vocab, math_samples(limit))
    print(f"english n={len(english)}  math n={len(math)}\n")

    print(f"{'rule':>12} {'gate':>6} {'run':>4} {'text acc':>9} {'math acc':>9} {'balanced':>9}")
    best = None
    for name, rule, gates, runs in [
        ("gate", gate_only, [0.70, 0.75, 0.80, 0.85, 0.90, 0.95], [0]),
        ("run", run_only, [0.0], [2, 3, 4, 5]),
        ("gate+run", gate_or_run, [0.70, 0.75, 0.80, 0.85, 0.90], [3, 4, 5]),
    ]:
        for gate in gates:
            for run_gate in runs:
                text_acc, math_acc, balanced = accuracy(rule, english, math, gate, run_gate)
                print(f"{name:>12} {gate:>6.2f} {run_gate:>4} {text_acc:>8.1%} {math_acc:>8.1%} {balanced:>8.1%}")
                if best is None or balanced > best[0]:
                    best = (balanced, name, gate, run_gate)
        print()

    print(f"best: {best[1]} gate={best[2]} run={best[3]} balanced={best[0]:.1%}")

    wired = accuracy(lambda row, g, r: route_kind(row["content"], row["confidence"]), english, math, 0, 0)
    print(f"wired (gate={MATH_CONFIDENCE_GATE}, run={LETTER_RUN_GATE}): text {wired[0]:.1%} math {wired[1]:.1%} balanced {wired[2]:.1%}")

    print("\nenglish misroutes (sample):")
    misses = [row for row in english if route_kind(row["content"], row["confidence"]) == "math"]
    for row in misses[:15]:
        print(f"  {row['confidence']:.3f}  {row['content'][:70]!r}")
    print(f"  ... {len(misses)} total")

    print("\nmath misroutes (sample):")
    misses = [row for row in math if route_kind(row["content"], row["confidence"]) == "text"]
    for row in misses[:15]:
        print(f"  {row['confidence']:.3f}  {row['content'][:70]!r}")
    print(f"  ... {len(misses)} total")


if __name__ == "__main__":
    main()
