import os
import sys
import glob
from multiprocessing import Pool, cpu_count

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from ctc.preprocessing import parse_inkml
from ocr_pipeline.recognizer import classify_kind

DATASET = "/Volumes/Games/mathwriting/mathwriting-2024"


def classify_label(path):
    _, label = parse_inkml(path)
    if not label:
        return None
    return {"label": label, "kind": classify_kind(label)}


def main():
    split = sys.argv[1] if len(sys.argv) > 1 else "train"
    limit = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    workers = int(sys.argv[3]) if len(sys.argv) > 3 else max(1, cpu_count() - 2)

    files = sorted(glob.glob(os.path.join(DATASET, split, "*.inkml")))
    if limit:
        files = files[:limit]

    print(f"split={split} files={len(files)} workers={workers}")

    with Pool(workers) as pool:
        results = [r for r in pool.imap_unordered(classify_label, files, chunksize=256) if r]

    total = len(results)
    math = sum(r["kind"] == "math" for r in results)

    print(f"\nprocessed={total}")
    print(f"labels classified math (latex): {math}/{total} = {math / total:.3%}")

    misroute = [r for r in results if r["kind"] != "math"]
    print(f"\nnon-math labels ({len(misroute)}):")
    for r in misroute[:40]:
        print(f"  {r['label']!r}")


if __name__ == "__main__":
    main()
