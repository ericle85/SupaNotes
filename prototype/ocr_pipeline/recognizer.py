"""CTC recognition + math-vs-text classification for stroke groups."""

from __future__ import annotations

import os
import re
from functools import lru_cache
from typing import Any

import numpy as np
from sympy import latex
import torch

from ocr_pipeline.ctc.model import CTCTransformer
from ocr_pipeline.ctc.dataset import Vocabulary, BLANK_TOKEN
from ocr_pipeline.ctc.preprocessing import normalize_strokes, extract_point_features, MAX_SEQ_LEN

MODELS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "models")
CKPT_PATH = os.path.join(MODELS_DIR, "ctc_final.pt")
VOCAB_PATH = os.path.join(MODELS_DIR, "vocab.json")
ROUTER_PATH = os.path.join(MODELS_DIR, "router.joblib")

D_MODEL = 256
NHEAD = 8
NUM_LAYERS = 6
DIM_FF = 1024
MAX_SEQ = 2048
INPUT_DIM = 6
CONFIDENCE_THRESHOLD = 0.5
TOP_K_ALTERNATIVES = 3
MATH_CONFIDENCE_GATE = 0.85
LETTER_RUN_GATE = 4

LATEX_COMMAND = re.compile(r"\\[a-zA-Z]+")
MATH_SYMBOL = re.compile(r"[0-9+=^_/*<>()&-]")
MATH_BRACKET = re.compile(r"[\[\]:,|{}]")
DOUBLED_BACKSLASH = re.compile(r"\\\\(?=[a-zA-Z])")
LETTER_RUN = re.compile(r"[a-zA-Z]+")
LATEX_ENVIRONMENT = re.compile(r"\\(?:begin|end)\{[a-zA-Z*]+\}")
# ponytail: function names only strip at a letter boundary, so "nlog" stays a run of 4.
# Dropping the boundary would shred English words ("along", "important"). Fix with a
# real feature classifier if the residual misroutes matter.
MATH_FUNCTION = re.compile(
    r"(?<![a-zA-Z])(?:arcsin|arccos|arctan|sqrt|sinh|cosh|tanh"
    r"|log|ln|exp|sin|cos|tan|sec|csc|cot|lim|max|min|sup|inf|det|dim|deg|gcd|mod|arg)"
)


@lru_cache(maxsize=1)
def load_recognizer() -> tuple[CTCTransformer, Vocabulary]:
    vocab = Vocabulary()
    vocab.load(VOCAB_PATH)
    checkpoint = torch.load(CKPT_PATH, map_location="cpu", weights_only=False)
    model = CTCTransformer(
        vocab_size=checkpoint["vocab_size"],
        input_dim=INPUT_DIM,
        d_model=D_MODEL,
        nhead=NHEAD,
        num_layers=NUM_LAYERS,
        dim_ff=DIM_FF,
        dropout=0,
        max_seq_len=MAX_SEQ // 2 + 2,
    )
    model.load_state_dict(checkpoint["model"])
    model.eval()
    return model, vocab


def strokes_in_writing_order(strokes: list[dict[str, Any]]) -> list[list[tuple[float, float, float]]]:
    ordered = sorted(strokes, key=lambda stroke: stroke.get("times", {}).get("start", 0.0))
    result = []
    for stroke in ordered:
        points = [(point["x"], point["y"], point["t"]) for point in stroke.get("points", [])]
        if len(points) >= 2:
            result.append(points)
    return result


def collapse_repeats(vocab: Vocabulary, predictions: list[int]) -> str:
    tokens = []
    previous = -1
    for token in predictions:
        if token != previous and token != BLANK_TOKEN:
            tokens.append(vocab.idx2tok.get(token, "?"))
        previous = token
    return "".join(tokens)


def step_alternatives(vocab: Vocabulary, step_probs: Any, chosen: int) -> list[dict[str, Any]]:
    count = min(TOP_K_ALTERNATIVES + 2, step_probs.shape[-1])
    top = torch.topk(step_probs, count)
    candidates = (
        {"token": vocab.idx2tok.get(idx, "?"), "confidence": round(prob, 4)}
        for prob, idx in zip(top.values.tolist(), top.indices.tolist())
        if idx != BLANK_TOKEN and idx != chosen
    )
    return list(candidates)[:TOP_K_ALTERNATIVES]


def collapse_with_confidence(vocab: Vocabulary, steps: Any) -> dict[str, Any]:
    probs = steps.exp()
    ids = steps.argmax(dim=-1).tolist()
    tokens = []
    previous = -1
    for index, token in enumerate(ids):
        if token != previous and token != BLANK_TOKEN:
            step_probs = probs[index]
            tokens.append(
                {
                    "token": vocab.idx2tok.get(token, "?"),
                    "confidence": round(step_probs[token].item(), 4),
                    "alternatives": step_alternatives(vocab, step_probs, token),
                }
            )
        previous = token
    content = DOUBLED_BACKSLASH.sub("\\\\", "".join(token["token"] for token in tokens))
    overall = round(sum(token["confidence"] for token in tokens) / len(tokens), 4) if tokens else 0.0
    return {"content": content, "confidence": overall, "tokens": tokens}


def decode(model: CTCTransformer, vocab: Vocabulary, raw_strokes: list[list[tuple[float, float, float]]]) -> dict[str, Any]:
    arrays = [np.array(stroke, dtype=np.float64) for stroke in raw_strokes if len(stroke) >= 2]
    if not arrays:
        return {"content": "", "confidence": 0.0, "tokens": []}
    features = extract_point_features(normalize_strokes(arrays))[:MAX_SEQ_LEN]
    lengths = torch.tensor([len(features)])
    with torch.no_grad():
        log_probs, out_lengths = model(torch.from_numpy(features).unsqueeze(0).float(), lengths)
    steps = log_probs[: out_lengths[0].item(), 0, :]
    return collapse_with_confidence(vocab, steps)


def classify_kind(content: str) -> str:
    latex_commands_removed = LATEX_COMMAND.sub(" ", content)
    if (
        LATEX_COMMAND.search(content)
        or MATH_SYMBOL.search(latex_commands_removed)
        or MATH_BRACKET.search(latex_commands_removed)
    ):
        return "math"
    return "text"


def longest_letter_run(content: str) -> int:
    stripped = MATH_FUNCTION.sub(" ", LATEX_COMMAND.sub(" ", LATEX_ENVIRONMENT.sub(" ", content)))
    return max((len(run) for run in LETTER_RUN.findall(stripped)), default=0)


def fraction(predicate, items) -> float:
    return sum(1.0 for item in items if predicate(item)) / len(items) if items else 0.0


def router_features(content: str, token_confidences: list[float]) -> list[float]:
    confidences = token_confidences or [0.0]
    ordered = sorted(confidences)
    mean = sum(confidences) / len(confidences)
    variance = sum((value - mean) ** 2 for value in confidences) / len(confidences)
    quantile = lambda q: ordered[min(len(ordered) - 1, int(q * len(ordered)))]
    letters_only = LATEX_COMMAND.sub(" ", content)
    return [
        mean,
        ordered[0],
        variance**0.5,
        quantile(0.10),
        quantile(0.25),
        quantile(0.50),
        fraction(lambda value: value < 0.5, confidences),
        fraction(lambda value: value < 0.9, confidences),
        min(longest_letter_run(content), 8) / 8.0,
        fraction(str.isalpha, letters_only),
        fraction(str.isdigit, letters_only),
        fraction(lambda char: bool(MATH_SYMBOL.match(char)), letters_only),
        fraction(lambda char: bool(MATH_BRACKET.match(char)), letters_only),
        len(LATEX_COMMAND.findall(content)) / len(confidences),
        1.0 if "=" in content else 0.0,
        1.0 if ("_" in content or "^" in content) else 0.0,
        1.0 if "\\frac" in content else 0.0,
    ]


def stroke_boxes(strokes) -> tuple:
    arrays = [np.asarray(stroke, dtype=np.float64)[:, :2] for stroke in strokes if len(stroke) >= 2]
    if not arrays:
        return None
    lows = np.array([array.min(axis=0) for array in arrays])
    highs = np.array([array.max(axis=0) for array in arrays])
    order = np.argsort((lows[:, 0] + highs[:, 0]) / 2)
    return lows[order], highs[order]


def stroke_layout_features(strokes) -> list[float]:
    boxes = stroke_boxes(strokes)
    if boxes is None:
        return [0.0] * 8
    lows, highs = boxes
    widths, heights = highs[:, 0] - lows[:, 0], highs[:, 1] - lows[:, 1]
    centers = (lows[:, 1] + highs[:, 1]) / 2
    unit = float(np.median(heights)) or float(np.max(heights)) or 1.0
    steps = np.abs(np.diff(centers)) if len(centers) > 1 else np.zeros(1)
    overlap = np.minimum(highs[:-1, 0], highs[1:, 0]) - np.maximum(lows[:-1, 0], lows[1:, 0])
    span = np.maximum(np.minimum(widths[:-1], widths[1:]), 1e-9)
    return [
        float(np.std(centers)) / unit,
        float(np.mean(np.abs(centers - np.median(centers)) > 0.5 * unit)),
        float(np.mean(steps)) / unit,
        float(np.mean(overlap / span > 0.5)) if len(widths) > 1 else 0.0,
        min(float(np.max(widths)) / unit, 20.0) / 20.0,
        float(np.mean(widths > 2 * np.maximum(heights, 1e-9))),
        float(np.std(heights)) / unit,
        float(np.mean(heights < 0.5 * unit)),
    ]


def route_kind(content: str, confidence: float) -> str:
    if confidence < MATH_CONFIDENCE_GATE or longest_letter_run(content) >= LETTER_RUN_GATE:
        return "text"
    return classify_kind(content)


@lru_cache(maxsize=1)
def load_router():
    if not os.path.exists(ROUTER_PATH):
        return None
    import joblib

    return joblib.load(ROUTER_PATH)


# TODO: Check if we can do this without the confidence per token and we use the logits instead.
def route_group(content: str, token_confidences: list[float], strokes) -> str:
    router = load_router()
    if router is None:
        mean = sum(token_confidences) / len(token_confidences) if token_confidences else 0.0
        return route_kind(content, mean)
    from scipy.sparse import csr_matrix, hstack

    numeric = router_features(content, token_confidences) + stroke_layout_features(strokes)
    features = hstack([router["vectorizer"].transform([content]), csr_matrix(np.array([numeric]))]).tocsr()
    probability = router["model"].predict_proba(features)[0, 1]
    return "math" if probability >= router["threshold"] else "text"


def recognize_group(group: dict[str, Any]) -> dict[str, Any]:
    strokes = strokes_in_writing_order(group["strokes"])
    if not strokes:
        return {"kind": "not labeled", "content": "", "confidence": 0.0, "tokens": []}
    model, vocab = load_recognizer()
    print("Decoding for group with {} strokes...".format(len(strokes)))
    result = decode(model, vocab, strokes)
    print(result["confidence"], result["content"])
    kind = route_group(result["content"], [token["confidence"] for token in result["tokens"]], strokes)
    is_math = (kind == "math")
    return {
        "kind": kind,
        "content": result["content"] if is_math else "",
        "confidence": result["confidence"] if is_math else 0.0,
        "tokens": result["tokens"] if is_math else [],
    }
