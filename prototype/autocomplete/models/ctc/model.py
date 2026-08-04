"""Conv + Transformer + CTC model for online handwriting recognition."""

import os
import math
import torch
import torch.nn as nn
import torch.nn.functional as F
import numpy as np

from .dataset import Vocabulary, BLANK_TOKEN
from .preprocessing import normalize_strokes, extract_point_features

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CKPT_PATH = os.path.join(SCRIPT_DIR, "ctc_final.pt")
VOCAB_PATH = os.path.join(SCRIPT_DIR, "vocab.json")
MAX_SEQ_LEN = 2048         # max input points
INNER_MAX_SEQ_LEN = 1026    # max transformer positions (matches checkpoint PE buffer)

class SinusoidalPositionalEncoding(nn.Module):
    def __init__(self, d_model, max_len=2048, dropout=0.1):
        super().__init__()
        self.dropout = nn.Dropout(dropout)
        pe = torch.zeros(max_len, d_model)
        pos = torch.arange(max_len).unsqueeze(1).float()
        div = torch.exp(torch.arange(0, d_model, 2).float() * (-math.log(10000.0) / d_model))
        pe[:, 0::2] = torch.sin(pos * div)
        pe[:, 1::2] = torch.cos(pos * div)
        self.register_buffer('pe', pe.unsqueeze(0))

    def forward(self, x):
        x = x + self.pe[:, :x.size(1)]
        return self.dropout(x)


class ConvSubsampler(nn.Module):
    """2x Conv1d blocks with stride 2 → 4x downsampling.

    Learns local stroke patterns and reduces sequence length for the transformer.
    """

    def __init__(self, input_dim, d_model, dropout=0.1):
        super().__init__()
        self.conv1 = nn.Conv1d(input_dim, d_model, kernel_size=5, stride=2, padding=2)
        self.conv2 = nn.Conv1d(d_model, d_model, kernel_size=5, stride=1, padding=2)
        self.conv3 = nn.Conv1d(d_model, d_model, kernel_size=3, stride=1, padding=1)
        self.norm1 = nn.LayerNorm(d_model)
        self.norm2 = nn.LayerNorm(d_model)
        self.norm3 = nn.LayerNorm(d_model)
        self.dropout = nn.Dropout(dropout)

    def forward(self, x):
        """x: (B, T, C) → (B, T//2, d_model)"""
        x = x.transpose(1, 2)  # (B, C, T)
        x = F.gelu(self.conv1(x))
        x = x.transpose(1, 2)  # (B, T', C)
        x = self.norm1(x)
        x = self.dropout(x)
        x = x.transpose(1, 2)  # (B, C, T')
        x = F.gelu(self.conv2(x))
        x = x.transpose(1, 2)  # (B, T'', C)
        x = self.norm2(x)
        x = self.dropout(x)
        x = x.transpose(1, 2)
        x = F.gelu(self.conv3(x))
        x = x.transpose(1, 2)
        x = self.norm3(x)
        x = self.dropout(x)
        return x

    @staticmethod
    def output_length(input_length):
        """Compute output sequence length after stride-2 + stride-1 convolutions."""
        l = (input_length - 1) // 2 + 1  # stride-2
        return l  # stride-1 preserves length


class CTCTransformer(nn.Module):
    """Conv frontend + Transformer encoder + CTC head.

    Architecture:
    - ConvSubsampler: 4x downsampling, learns local features
    - Sinusoidal positional encoding
    - N transformer encoder layers (pre-norm)
    - Linear CTC head + log_softmax
    """

    def __init__(self, vocab_size, input_dim=6, d_model=256, nhead=8,
                 num_layers=6, dim_ff=1024, dropout=0, max_seq_len=2048):
        super().__init__()
        self.conv = ConvSubsampler(input_dim, d_model, dropout=dropout)
        self.pos_enc = SinusoidalPositionalEncoding(d_model, max_len=max_seq_len, dropout=dropout)

        encoder_layer = nn.TransformerEncoderLayer(
            d_model=d_model, nhead=nhead, dim_feedforward=dim_ff,
            dropout=dropout, activation='gelu', batch_first=True,
            norm_first=True,
        )
        self.encoder = nn.TransformerEncoder(encoder_layer, num_layers=num_layers,
                                             enable_nested_tensor=False)
        self.ctc_head = nn.Linear(d_model, vocab_size)
        self.vocab_size = vocab_size

    def forward(self, x, lengths=None):
        """
        Args:
            x: (B, T, input_dim) raw point features
            lengths: (B,) input lengths
        Returns:
            ctc_log_probs: (T', B, vocab_size) where T' = T//4
            out_lengths: (B,) output lengths after conv subsampling
        """
        # Conv subsampling
        x = self.conv(x)  # (B, T//4, d_model)
        _, T_out, _ = x.shape

        # Compute output lengths
        out_lengths = None
        if lengths is not None:
            out_lengths = ConvSubsampler.output_length(lengths)

        # Positional encoding
        x = self.pos_enc(x)

        # Padding mask
        src_key_padding_mask = None
        if out_lengths is not None:
            src_key_padding_mask = torch.arange(T_out, device=x.device).unsqueeze(0) >= out_lengths.unsqueeze(1)

        x = self.encoder(x, src_key_padding_mask=src_key_padding_mask)
        logits = self.ctc_head(x)
        log_probs = F.log_softmax(logits, dim=-1).permute(1, 0, 2)  # (T', B, V)
        return log_probs, out_lengths


def ctc_greedy_decode(log_probs, lengths, vocab):
    preds = log_probs.argmax(dim=-1).T  # (B, T)
    results = []
    for i, length in enumerate(lengths):
        seq = preds[i, :length].tolist()
        decoded = []
        prev = -1
        for tok in seq:
            if tok != prev and tok != BLANK_TOKEN:
                decoded.append(tok)
            prev = tok
        results.append(vocab.decode(decoded))
    return results


class CTCModel:
    """Ready-to-use CTC handwriting recognition model.

    Loads the checkpoint and vocabulary on construction — no extra setup needed.

    Usage:
        model = CTCModel()
        text = model.transcribe(strokes)
    """

    def __init__(self):
        ckpt = torch.load(CKPT_PATH, map_location="cpu", weights_only=False)

        self.vocab = Vocabulary()
        self.vocab.load(VOCAB_PATH)

        self.ctc = CTCTransformer(
            vocab_size=ckpt["vocab_size"],
            max_seq_len=INNER_MAX_SEQ_LEN,
        )
        self.ctc.load_state_dict(ckpt["model"])
        self.ctc.eval()

    @torch.no_grad()
    def transcribe(self, strokes):
        """Transcribe handwritten strokes to LaTeX text.

        Args:
            strokes: list of np.ndarrays, each shape (N_i, 3) with columns [x, y, t]

        Returns:
            str: decoded transcription
        """
        if not strokes:
            return ""

        strokes = normalize_strokes(strokes)
        features = extract_point_features(strokes)

        if len(features) == 0 or len(features) > MAX_SEQ_LEN:
            return ""

        x = torch.from_numpy(features).float().unsqueeze(0)  # (1, N, 6)
        lengths = torch.tensor([features.shape[0]], dtype=torch.long)

        ctc_log_probs, out_lens = self.ctc(x, lengths)
        results = ctc_greedy_decode(ctc_log_probs.cpu(), out_lens.cpu(), self.vocab)

        return results[0]