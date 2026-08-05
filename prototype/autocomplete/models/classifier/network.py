import torch
from torch import nn
import numpy as np
from typing import Iterable

NUM_CLASSES = 4

class StrokeClassifier(nn.Module):
    """
    Classifier model for online handwriting strokes. Input is a sequence of shape (N, 5) with features (x, y, dx, dy, pen_state). Output is a vector of class logits.
    """

    def __init__(
        self,
        input_features: int = 5,
        num_classes: int = NUM_CLASSES,
        width: int = 32,
    ):
        super().__init__()
        if width < 4:
            raise ValueError(f"Model width must be at least 4, got {width}")
        mid_width = width * 3 // 2
        final_width = width * 2
        self.encoder = nn.Sequential(
            nn.Conv1d(input_features, width, kernel_size=7, padding=3),
            nn.BatchNorm1d(width),
            nn.GELU(),
            nn.Conv1d(width, mid_width, kernel_size=7, padding=3),
            nn.BatchNorm1d(mid_width),
            nn.GELU(),
            nn.MaxPool1d(2),
            nn.Conv1d(mid_width, final_width, kernel_size=5, padding=2),
            nn.BatchNorm1d(final_width),
            nn.GELU(),
            nn.Conv1d(final_width, final_width, kernel_size=5, padding=2),
            nn.BatchNorm1d(final_width),
            nn.GELU(),
        )
        self.head = nn.Sequential(
            nn.Linear(final_width * 2, final_width),
            nn.GELU(),
            nn.Dropout(0.2),
            nn.Linear(final_width, num_classes),
        )

    def forward(self, inputs: torch.Tensor) -> torch.Tensor:
        encoded = self.encoder(inputs.transpose(1, 2))
        pooled = torch.cat((encoded.mean(dim=-1), encoded.amax(dim=-1)), dim=1)
        return self.head(pooled)


def strokes_to_classifier_sequence(strokes: Iterable[np.ndarray]) -> np.ndarray:
    parts: list[np.ndarray] = []
    for stroke in strokes:
        array = np.asarray(stroke, dtype=np.float32)
        if array.ndim != 2 or array.shape[1] < 2 or len(array) < 2:
            continue
        xy = array[:, :2]
        pen = np.zeros((len(xy), 1), dtype=np.float32)
        pen[0, 0] = 1.0
        parts.append(np.concatenate([xy, pen], axis=1))
    if not parts:
        raise ValueError("No strokes were available for classification")
    return np.concatenate(parts, axis=0)


def normalize_sequence(sequence: np.ndarray, length: int = 160) -> np.ndarray:
    """Normalize and resample a raw online trace to ``length x 5`` features."""

    array = np.asarray(sequence, dtype=np.float32)
    if array.ndim != 2 or array.shape[1] < 2 or len(array) == 0:
        raise ValueError(f"Expected a non-empty N x >=2 sequence, got {array.shape}")
    array = array[np.isfinite(array[:, :2]).all(axis=1)]
    if len(array) == 0:
        raise ValueError("Sequence contains no finite points")
    xy = array[:, :2].copy()
    lo = xy.min(axis=0)
    span = float(np.max(xy.max(axis=0) - lo))
    span = max(span, 1e-5)
    xy = (xy - lo) / span * 2.0 - 1.0
    pen = np.clip(array[:, 2] if array.shape[1] >= 3 else np.zeros(len(array)), 0.0, 1.0)

    old_grid = np.linspace(0.0, 1.0, len(xy), dtype=np.float32)
    new_grid = np.linspace(0.0, 1.0, length, dtype=np.float32)
    resampled = np.column_stack(
        [np.interp(new_grid, old_grid, xy[:, column]) for column in range(2)]
    ).astype(np.float32)
    pen_indices = np.minimum((new_grid * max(len(xy) - 1, 1)).round().astype(np.int64), len(pen) - 1)
    resampled_pen = pen[pen_indices].astype(np.float32)
    delta = np.vstack((np.zeros((1, 2), dtype=np.float32), np.diff(resampled, axis=0)))
    return np.column_stack((resampled, delta, resampled_pen)).astype(np.float32)


def featurize(sequences: Iterable[np.ndarray], length: int) -> np.ndarray:
    features = [normalize_sequence(sequence, length) for sequence in sequences]
    if not features:
        raise ValueError("No sequences were available")
    return np.stack(features).astype(np.float32)