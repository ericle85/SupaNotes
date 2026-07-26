import os
import re
import tkinter as tk
import numpy as np
import torch

from ocr_pipeline.ctc.model import CTCTransformer
from ocr_pipeline.ctc.dataset import Vocabulary, BLANK_TOKEN
from ocr_pipeline.ctc.preprocessing import normalize_strokes, extract_point_features, MAX_SEQ_LEN
from autocomplete.autocomplete_pipeline import run_autocomplete_on_document_text

MODELS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ocr_pipeline", "models")
CKPT_PATH = os.path.join(MODELS_DIR, "ctc_final.pt")
VOCAB_PATH = os.path.join(MODELS_DIR, "vocab.json")

D_MODEL = 256
NHEAD = 8
NUM_LAYERS = 6
DIM_FF = 1024
DROPOUT = 0
MAX_SEQ = 2048
INPUT_DIM = 6
CONFIDENCE_THRESHOLD = 0.5


def load_recognizer():
    vocab = Vocabulary()
    vocab.load(VOCAB_PATH)
    ckpt = torch.load(CKPT_PATH, map_location="cpu", weights_only=False)
    model = CTCTransformer(
        vocab_size=ckpt["vocab_size"],
        input_dim=INPUT_DIM,
        d_model=D_MODEL,
        nhead=NHEAD,
        num_layers=NUM_LAYERS,
        dim_ff=DIM_FF,
        dropout=DROPOUT,
        max_seq_len=MAX_SEQ // 2 + 2,
    )
    model.load_state_dict(ckpt["model"])
    model.eval()
    print(f"model loaded: step={ckpt['step']}, vocab={ckpt['vocab_size']}")
    return model, vocab


def clean_recognized_latex(text):
    return re.sub(r"\\\\(?=[a-zA-Z])", r"\\", text)


def recognize_strokes(model, vocab, raw_strokes):
    strokes = [np.array(s, dtype=np.float64) for s in raw_strokes if len(s) >= 2]
    if not strokes:
        return "", []
    strokes = normalize_strokes(strokes)
    features = extract_point_features(strokes)
    if len(features) > MAX_SEQ_LEN:
        features = features[:MAX_SEQ_LEN]
    feat_t = torch.from_numpy(features).unsqueeze(0).float()
    feat_lens = torch.tensor([len(features)])
    with torch.no_grad():
        log_probs, out_lens = model(feat_t, feat_lens)
    tokens = ctc_greedy_decode_with_confidence(
        log_probs.float().cpu(), out_lens.cpu(), vocab, CONFIDENCE_THRESHOLD
    )
    return clean_recognized_latex(tokens["raw"]), tokens["tokens"]


def ctc_greedy_decode_with_confidence(log_probs, lengths, vocab, threshold):
    probs = log_probs.exp()
    preds = log_probs.argmax(dim=-1).T
    max_probs = probs.max(dim=-1).values.T
    seq = preds[0, : lengths[0].item()].tolist()
    confs = max_probs[0, : lengths[0].item()].tolist()
    decoded = []
    prev = -1
    for tok, conf in zip(seq, confs):
        if tok != prev and tok != BLANK_TOKEN:
            decoded.append((tok, conf))
        elif tok == prev and tok != BLANK_TOKEN and decoded:
            old_tok, old_conf = decoded[-1]
            decoded[-1] = (old_tok, max(old_conf, conf))
        prev = tok
    parts = [vocab.idx2tok.get(tok, "?") for tok, _ in decoded]
    return {"raw": "".join(parts), "tokens": decoded}


class DrawAndAutosuggestApp:
    def __init__(self, root, model, vocab):
        self.root = root
        self.model = model
        self.vocab = vocab
        self.strokes = []
        self.current_stroke = []
        self.drawing = False
        self.t0 = 0.0

        root.title("SupaNotes — draw math, get autocomplete")
        root.configure(bg="#1a1a2e")

        self.canvas = tk.Canvas(root, width=700, height=300, bg="#16213e", highlightthickness=2, highlightbackground="#555")
        self.canvas.pack(padx=10, pady=10)
        self.canvas.bind("<ButtonPress-1>", self.start_draw)
        self.canvas.bind("<B1-Motion>", self.draw)
        self.canvas.bind("<ButtonRelease-1>", self.end_draw)

        button_row = tk.Frame(root, bg="#1a1a2e")
        button_row.pack(pady=4)
        tk.Button(button_row, text="Predict + Autosuggest", command=self.predict_and_suggest, bg="#2ecc71", fg="white", padx=12).pack(side=tk.LEFT, padx=6)
        tk.Button(button_row, text="Clear", command=self.clear, bg="#e74c3c", fg="white", padx=12).pack(side=tk.LEFT, padx=6)

        self.recognized_var = tk.StringVar(value="recognized: —")
        tk.Label(root, textvariable=self.recognized_var, bg="#1a1a2e", fg="#00d2ff", font=("Menlo", 18)).pack(pady=(10, 2))

        self.suggestion_var = tk.StringVar(value="suggestion: —")
        tk.Label(root, textvariable=self.suggestion_var, bg="#1a1a2e", fg="#2ecc71", font=("Menlo", 22)).pack(pady=(2, 10))

        self.status_var = tk.StringVar(value="draw a math expression, then click Predict")
        tk.Label(root, textvariable=self.status_var, bg="#1a1a2e", fg="#888", font=("Menlo", 11)).pack(pady=(0, 10))

    def start_draw(self, event):
        self.drawing = True
        if not self.strokes and not self.current_stroke:
            self.t0 = event.time / 1000.0
        self.current_stroke = [(event.x, event.y, event.time / 1000.0 - self.t0)]
        self.canvas.create_oval(event.x - 1, event.y - 1, event.x + 1, event.y + 1, fill="#00d2ff", outline="")

    def draw(self, event):
        if not self.drawing:
            return
        prev_x, prev_y, _ = self.current_stroke[-1]
        self.current_stroke.append((event.x, event.y, event.time / 1000.0 - self.t0))
        self.canvas.create_line(prev_x, prev_y, event.x, event.y, fill="#00d2ff", width=2, capstyle=tk.ROUND, smooth=True)

    def end_draw(self, _event):
        if not self.drawing:
            return
        self.drawing = False
        if len(self.current_stroke) >= 2:
            self.strokes.append(self.current_stroke)
        self.current_stroke = []

    def clear(self):
        self.strokes = []
        self.current_stroke = []
        self.canvas.delete("all")
        self.recognized_var.set("recognized: —")
        self.suggestion_var.set("suggestion: —")
        self.status_var.set("cleared — draw a math expression")

    def predict_and_suggest(self):
        if not self.strokes:
            self.status_var.set("nothing drawn yet")
            return
        self.status_var.set("recognizing…")
        self.root.update()
        raw, _tokens = recognize_strokes(self.model, self.vocab, self.strokes)
        if not raw.strip():
            self.recognized_var.set("recognized: (empty)")
            self.suggestion_var.set("suggestion: —")
            self.status_var.set("model produced no output")
            return
        self.recognized_var.set(f"recognized: {raw}")
        self.status_var.set("running autocomplete…")
        self.root.update()
        result = run_autocomplete_on_document_text(raw)
        if result.suggestion.has_suggestion:
            self.suggestion_var.set(f"suggestion: {result.suggestion.suggested_text}")
            print(f"RECOGNIZED: {raw!r}")
            print(f"SUGGESTION: {result.suggestion.suggested_text!r}")
            print(f"OPERATION:  {result.classified_intent.operation.name}")
        else:
            self.suggestion_var.set("suggestion: (none)")
            print(f"RECOGNIZED: {raw!r}")
            print(f"NO SUGGESTION: {result.suggestion.diagnostic_reason!r}")
        self.status_var.set("done")


def main():
    model, vocab = load_recognizer()
    root = tk.Tk()
    DrawAndAutosuggestApp(root, model, vocab)
    root.mainloop()


if __name__ == "__main__":
    main()
