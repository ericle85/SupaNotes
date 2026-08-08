from models.classifier.model import ClassifierModel
from models.ctc.model import CTCModel
from math_engine.engine import do_autosuggestion

ctc_model = CTCModel()
classifier_model = ClassifierModel()

def pipeline(strokes) -> str:
    kind = classify_strokes(strokes)
    print(f"kind: {kind}")
    if kind == "scribble" or kind == "none":
        return

    strokes_as_string = translate_strokes_to_string(strokes, kind)
    print(f"strokes as strings: {strokes_as_string}")
    suggestion = get_autosuggestion(strokes_as_string, kind)
    print(f"suggestion: {suggestion}")
    return suggestion

def classify_strokes(strokes) -> str:
    result = classifier_model.classify(strokes)
    print(f"classify results: {result}")
    return result["class"]

def translate_strokes_to_string(strokes, kind) -> str:
    if kind == "math":
        return ctc_model.transcribe(strokes)
    if kind == "writing":
        # TODO: use google digital ink ml which is IOS only
        return "PLACE HOLDER GOOGLE"
    raise NotImplementedError

def get_autosuggestion(strokes_as_string, kind) -> str:
    if kind == "math":
        return do_autosuggestion(strokes_as_string)
    
    if kind == "writing":
        return "place holder google"
    raise NotImplementedError



def load_deepwriting_sample(path, index=0):
    import numpy as np

    with np.load(path, allow_pickle=True) as data:
        sample = data["strokes"][index].copy()
        mean, std = data["mean"], data["std"]
        scale_min, scale_max = data["min"], data["max"]

    pen = sample[:, 2].copy()
    s = sample[:, :3].copy()
    s[:, [0, 1]] = (s * std + mean)[:, [0, 1]]
    s = np.cumsum(s, axis=0)
    s[:, :2] = s[:, :2] * (scale_max[:2] - scale_min[:2]) + scale_min[:2]
    s[:, 2] = (pen > 0.5).astype(np.float32)

    segments = []
    start = 0
    for i in range(len(s)):
        if s[i, 2] > 0.5 or i == len(s) - 1:
            end = i + 1 if s[i, 2] <= 0.5 else i
            if end - start > 1:
                segments.append(s[start:end, :2])
            start = i + 1
    return segments


if __name__ == "__main__":
    import sys
    import json
    import numpy as np
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--english", action="store_true")
    parser.add_argument("--stdin", action="store_true")
    args, _ = parser.parse_known_args()

    if args.english:
        strokes = load_deepwriting_sample("samples/deepwriting_validation.npz")
        pipeline(strokes)
    elif args.stdin:
        raw = json.load(sys.stdin)
        strokes = [np.array(s) for s in raw]
        result = pipeline(strokes)
        print(json.dumps({"result": result}))
    else:
        from models.ctc.preprocessing import parse_inkml
        strokes, _ = parse_inkml("samples/math.inkml")
        pipeline(strokes)