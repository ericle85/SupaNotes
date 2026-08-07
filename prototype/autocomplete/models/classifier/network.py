import torch
from torch import nn
import numpy as np

NUM_CLASSES = 4


class StrokeClassifier(nn.Module):

    def __init__(
        self,
        input_features: int = 3,
        num_classes: int = NUM_CLASSES,
        width: int = 32,
    ):
        super().__init__()
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


def normalize_sequence(strokes, length=160):
    all_xy = np.concatenate([np.asarray(s, dtype=np.float32)[:, :2] for s in strokes], axis=0)
    all_xy = all_xy[np.isfinite(all_xy).all(axis=1)]
    if len(all_xy) == 0:
        raise ValueError("No finite points in strokes")

    lo = all_xy.min(axis=0)
    span = float(np.max(all_xy.max(axis=0) - lo))
    span = max(span, 1e-5)
    xy = (all_xy - lo) / span * 2.0 - 1.0

    old_grid = np.linspace(0.0, 1.0, len(xy), dtype=np.float32)
    new_grid = np.linspace(0.0, 1.0, length, dtype=np.float32)
    resampled = np.column_stack(
        [np.interp(new_grid, old_grid, xy[:, c]) for c in range(2)]
    ).astype(np.float32)
    t = np.zeros((length, 1), dtype=np.float32)
    return np.column_stack((resampled, t)).astype(np.float32)
