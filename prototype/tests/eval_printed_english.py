import os
import sys
import random
import contextlib
import io

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import torch

from ocr_pipeline.recognizer import load_recognizer, decode, route_group, route_kind

UJIPEN = "/Volumes/Games/ujipen/ujipenchars2.txt"

WORDS = """the of and to in a is that it for as with was on be by not this are but from they
his her she him have has had will would can could should may might must shall do does did
meeting notes agenda action items follow up review draft final version summary report update
project team client budget deadline schedule status blocked risk owner next steps question
buy milk eggs bread coffee call dentist book flight pay rent renew passport water plants
remember to send the email before noon and check the shared folder for the latest numbers
idea maybe try another approach here since the first one did not work very well at all
todo fix the bug in the parser and add a test case for the empty input path tomorrow""".split()

PUNCTUATION = [",", ".", ":", "?", "!", "-"]


def parse_ujipen(path):
    samples = {}
    label = writer = None
    pending = 0
    strokes = []
    for line in open(path, encoding="utf-8", errors="replace"):
        line = line.strip()
        if line.startswith("WORD "):
            if label is not None and strokes:
                samples.setdefault((writer, label), []).append(strokes)
            parts = line.split()
            label, writer = parts[1], parts[2].split("-")[0]
            strokes, pending = [], 0
        elif line.startswith("NUMSTROKES"):
            pending = int(line.split()[1])
        elif line.startswith("POINTS") and pending:
            numbers = [int(value) for value in line.split("#")[1].split()]
            points = list(zip(numbers[0::2], numbers[1::2]))
            if len(points) >= 2:
                strokes.append(points)
    if label is not None and strokes:
        samples.setdefault((writer, label), []).append(strokes)
    return samples


def glyph_extent(strokes):
    points = [point for stroke in strokes for point in stroke]
    xs = [x for x, _ in points]
    return min(xs), max(xs)


def compose(samples, writer, characters, rng):
    available = [character for character in characters if (writer, character) in samples]
    if len(available) != len(characters):
        return None
    cursor = 0.0
    placed = []
    widths = []
    for character in characters:
        if character == " ":
            cursor += 2.2 * (np.median(widths) if widths else 400.0)
            continue
        glyph = rng.choice(samples[(writer, character)])
        low, high = glyph_extent(glyph)
        widths.append(high - low)
        shift = cursor - low
        placed += [[(x + shift, float(y)) for x, y in stroke] for stroke in glyph]
        cursor += (high - low) + 0.35 * (high - low)
    return [[(x, y, float(index)) for index, (x, y) in enumerate(stroke)] for stroke in placed]


def sentence(rng):
    count = rng.choice([1, 1, 2, 2, 3, 3, 4, 5, 6])
    words = [rng.choice(WORDS) for _ in range(count)]
    text = " ".join(words)
    if rng.random() < 0.4:
        text = text[0].upper() + text[1:]
    if rng.random() < 0.35:
        text += rng.choice(PUNCTUATION)
    return text


def build(samples, rng, total, single_characters):
    writers = sorted({writer for writer, _ in samples})
    built = []
    attempts = 0
    while len(built) < total and attempts < total * 20:
        attempts += 1
        writer = rng.choice(writers)
        text = rng.choice("abcdefghijklmnopqrstuvwxyz") if single_characters else sentence(rng)
        strokes = compose(samples, writer, list(text), rng)
        if strokes:
            built.append((text, strokes))
    return built


def evaluate(model, vocab, cases, name):
    routed_text = 0
    rule_text = 0
    misroutes = []
    for text, strokes in cases:
        with contextlib.redirect_stdout(io.StringIO()):
            result = decode(model, vocab, strokes)
        kind = route_group(result["content"], [t["confidence"] for t in result["tokens"]], strokes)
        rule_text += route_kind(result["content"], result["confidence"]) == "text"
        if kind == "text":
            routed_text += 1
        else:
            misroutes.append((text, result["content"], result["confidence"]))
    print(f"\n{name}: router {routed_text}/{len(cases)} = {routed_text / len(cases):.1%}"
          f"   old rule {rule_text / len(cases):.1%}")
    for text, content, confidence in misroutes[:12]:
        print(f"  wrote {text[:28]!r:32} read {content[:36]!r:40} conf {confidence:.3f}")
    if len(misroutes) > 12:
        print(f"  ... {len(misroutes)} misroutes total")
    return routed_text / len(cases)


def main():
    count = int(sys.argv[1]) if len(sys.argv) > 1 else 400
    rng = random.Random(0)
    torch.set_num_threads(max(1, os.cpu_count() - 2))

    samples = parse_ujipen(UJIPEN)
    print(f"parsed {sum(len(v) for v in samples.values())} glyph samples from {len({w for w, _ in samples})} writers")

    with contextlib.redirect_stdout(io.StringIO()):
        model, vocab = load_recognizer()

    evaluate(model, vocab, build(samples, rng, count, single_characters=False), "printed words/lines")
    evaluate(model, vocab, build(samples, rng, count // 4, single_characters=True), "isolated single letters")


if __name__ == "__main__":
    main()
