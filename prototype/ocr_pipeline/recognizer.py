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


_DECODE_CACHE: dict[tuple, str] = {}


def decode(model: CTCTransformer, vocab: Vocabulary, raw_strokes: list[list[tuple[float, float, float]]]) -> str:
    arrays = [np.array(stroke, dtype=np.float64) for stroke in raw_strokes if len(stroke) >= 2]
    if not arrays:
        return ""
    key = tuple(tuple(map(tuple, stroke)) for stroke in raw_strokes if len(stroke) >= 2)
    cached = _DECODE_CACHE.get(key)
    if cached is not None:
        return cached
    features = extract_point_features(normalize_strokes(arrays))[:MAX_SEQ_LEN]
    feature_tensor = torch.from_numpy(features).unsqueeze(0).float()
    lengths = torch.tensor([len(features)])
    with torch.no_grad():
        log_probs, out_lengths = model(feature_tensor, lengths)
    predictions = log_probs.argmax(dim=-1).T[0, : out_lengths[0].item()].tolist()
    tokens = []
    previous = -1
    for token in predictions:
        if token != previous and token != BLANK_TOKEN:
            tokens.append(vocab.idx2tok.get(token, "?"))
        previous = token
    result = DOUBLED_BACKSLASH.sub("\\\\", "".join(tokens))
    _DECODE_CACHE[key] = result
    return result


def classify_kind(latex: str) -> str:
    body = LATEX_COMMAND.sub(" ", latex)
    longest_word = max((len(word) for word in WORD.findall(body)), default=0)
    if longest_word >= 3:
        return "text"
    if MATH_SYMBOL.search(body) or LATEX_MATH_COMMAND.search(latex):
        return "math"
    return "text"


def recognize_group(group: dict[str, Any]) -> dict[str, str]:
    strokes = strokes_in_writing_order(group["strokes"])
    if not strokes:
        return {"kind": "not labeled", "content": ""}
    model, vocab = load_recognizer()
    latex = decode(model, vocab, strokes)
    kind = classify_kind(latex)
    return {"kind": kind, "content": latex if kind == "math" else ""}
