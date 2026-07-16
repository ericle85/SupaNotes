"""Conv + Transformer + CTC model for online handwriting recognition."""

import math
import torch
import torch.nn as nn
import torch.nn.functional as F


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

    def __init__(self, vocab_size, input_dim=6, d_model=512, nhead=8,
                 num_layers=11, dim_ff=2048, dropout=0.15, max_seq_len=512):
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
