"""CTC recognition + math-vs-text classification for stroke groups."""

from __future__ import annotations

import os
import re
from functools import lru_cache
from typing import Any

import numpy as np
import torch

from ctc.model import CTCTransformer
from ctc.dataset import Vocabulary, BLANK_TOKEN
from ctc.preprocessing import normalize_strokes, extract_point_features, MAX_SEQ_LEN

PROTOTYPE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CKPT_PATH = os.path.join(PROTOTYPE_DIR, "ctc_final.pt")
VOCAB_PATH = os.path.join(PROTOTYPE_DIR, "vocab.json")

D_MODEL = 256
NHEAD = 8
NUM_LAYERS = 6
DIM_FF = 1024
MAX_SEQ = 2048
INPUT_DIM = 6
CONFIDENCE_THRESHOLD = 0.5
TOP_K_ALTERNATIVES = 3

LATEX_COMMAND = re.compile(r"\\[a-zA-Z]+")
LATEX_MATH_COMMAND = re.compile(r"\\(frac|sqrt|sum|int|cdot|times|div|pm|leq|geq|neq|infty)")
MATH_SYMBOL = re.compile(r"[0-9+=^_/*<>()-]")
WORD = re.compile(r"[A-Za-z]+")
DOUBLED_BACKSLASH = re.compile(r"\\\\(?=[a-zA-Z])")


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


def classify_kind(latex: str) -> str:
    body = LATEX_COMMAND.sub(" ", latex)
    longest_word = max((len(word) for word in WORD.findall(body)), default=0)
    if longest_word >= 3:
        return "text"
    if MATH_SYMBOL.search(body) or LATEX_MATH_COMMAND.search(latex):
        return "math"
    return "text"


def recognize_group(group: dict[str, Any]) -> dict[str, Any]:
    strokes = strokes_in_writing_order(group["strokes"])
    if not strokes:
        return {"kind": "not labeled", "content": "", "confidence": 0.0, "tokens": []}
    model, vocab = load_recognizer()
    print("Decoding for group with {} strokes...".format(len(strokes)))
    result = decode(model, vocab, strokes)
    kind = classify_kind(result["content"])
    is_math = kind == "math"
    return {
        "kind": kind,
        "content": result["content"] if is_math else "",
        "confidence": result["confidence"] if is_math else 0.0,
        "tokens": result["tokens"] if is_math else [],
    }
