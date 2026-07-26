import os
import sys
import glob
import contextlib
import io

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import torch

from ctc.preprocessing import parse_inkml
from ocr_pipeline.recognizer import load_recognizer, decode, classify_kind, route_kind, MATH_CONFIDENCE_GATE

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
        rows.append((result["content"], result["confidence"]))
    return rows


def report(name, stat):
    print(f"{name:22} mean={stat.mean():.3f} p10={np.percentile(stat, 10):.3f} p50={np.percentile(stat, 50):.3f} p90={np.percentile(stat, 90):.3f}")


def main():
    limit = int(sys.argv[1]) if len(sys.argv) > 1 else 705
    torch.set_num_threads(max(1, os.cpu_count() - 2))

    with contextlib.redirect_stdout(io.StringIO()):
        model, vocab = load_recognizer()

    english = decode_all(model, vocab, english_samples())
    math = decode_all(model, vocab, math_samples(limit))

    eng_conf = np.array([c for _, c in english])
    math_conf = np.array([c for _, c in math])

    print(f"english n={len(english)}  math n={len(math)}\n")
    report("english (deepwriting)", eng_conf)
    report("math (mathwriting)", math_conf)

    print("\nthreshold sweep:")
    print(f"{'gate':>6} {'text caught':>12} {'math lost':>10} {'text acc':>9} {'math acc':>9} {'balanced':>9}")
    for gate in [0.70, 0.75, 0.80, 0.85, 0.90, 0.95]:
        eng_text = np.mean([(route_at(c, content, gate) == "text") for content, c in english])
        math_math = np.mean([(route_at(c, content, gate) == "math") for content, c in math])
        print(f"{gate:>6.2f} {(eng_conf < gate).mean():>11.1%} {(math_conf < gate).mean():>10.1%} {eng_text:>8.1%} {math_math:>8.1%} {(eng_text + math_math) / 2:>8.1%}")

    print(f"\nwired gate = {MATH_CONFIDENCE_GATE}")
    eng_correct = sum(route_kind(content, c) == "text" for content, c in english)
    math_correct = sum(route_kind(content, c) == "math" for content, c in math)
    print(f"english routed text: {eng_correct}/{len(english)} = {eng_correct / len(english):.1%}")
    print(f"math routed math:    {math_correct}/{len(math)} = {math_correct / len(math):.1%}")

    baseline = sum(classify_kind(content) == "text" for content, _ in english)
    print(f"\nregex-only english→text (no gate): {baseline}/{len(english)} = {baseline / len(english):.1%}")


def route_at(confidence, content, gate):
    if confidence < gate:
        return "text"
    return classify_kind(content)


if __name__ == "__main__":
    main()
