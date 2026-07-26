import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from ocr_pipeline.recognizer import classify_kind

LABELS = "/Volumes/Games/hme100k/hme100k/train.txt"


def labels():
    with open(LABELS) as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) == 2 and parts[1]:
                yield parts[1]


def main():
    results = [(label, classify_kind(label)) for label in labels()]
    total = len(results)
    math = sum(kind == "math" for _, kind in results)

    print(f"processed={total}")
    print(f"labels classified math (latex): {math}/{total} = {math / total:.3%}")

    misroute = [label for label, kind in results if kind != "math"]
    print(f"\nnon-math labels ({len(misroute)}):")
    for label in misroute[:40]:
        print(f"  {label!r}")


if __name__ == "__main__":
    main()
