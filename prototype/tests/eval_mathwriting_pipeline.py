import os
import sys
import glob
from multiprocessing import Pool, cpu_count

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

DATASET = "/Volumes/Games/mathwriting/mathwriting-2024"

_model = None
_vocab = None


def _init_worker():
    global _model, _vocab
    import contextlib
    import io

    import torch

    torch.set_num_threads(1)
    with contextlib.redirect_stdout(io.StringIO()):
        from ocr_pipeline.recognizer import load_recognizer

        _model, _vocab = load_recognizer()


def evaluate_file(path):
    import contextlib
    import io

    from ctc.preprocessing import parse_inkml
    from ocr_pipeline.recognizer import decode, classify_kind

    strokes, label = parse_inkml(path)
    if not strokes:
        return None
    with contextlib.redirect_stdout(io.StringIO()):
        result = decode(_model, _vocab, strokes)
    content = result["content"]
    return {
        "label": label,
        "content": content,
        "kind": classify_kind(content),
        "exact": content == label,
    }


def main():
    split = sys.argv[1] if len(sys.argv) > 1 else "test"
    limit = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    workers = int(sys.argv[3]) if len(sys.argv) > 3 else max(1, cpu_count() - 2)

    files = sorted(glob.glob(os.path.join(DATASET, split, "*.inkml")))
    if limit:
        files = files[:limit]

    print(f"split={split} files={len(files)} workers={workers}")

    with Pool(workers, initializer=_init_worker) as pool:
        results = [r for r in pool.imap_unordered(evaluate_file, files, chunksize=32) if r]

    total = len(results)
    math = sum(r["kind"] == "math" for r in results)
    exact = sum(r["exact"] for r in results)

    print(f"\nprocessed={total}")
    print(f"classified math (latex): {math}/{total} = {math / total:.2%}")
    print(f"exact-match latex:       {exact}/{total} = {exact / total:.2%}")

    misroute = [r for r in results if r["kind"] != "math"]
    print(f"\nnon-math routed ({len(misroute)}):")
    for r in misroute[:30]:
        print(f"  label={r['label']!r} content={r['content']!r}")


if __name__ == "__main__":
    main()
