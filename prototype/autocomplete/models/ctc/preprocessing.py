"""InkML parser + point-level resampling for handwritten math recognition."""

import xml.etree.ElementTree as ET
import numpy as np
from typing import List, Tuple


# --- Tunable constants ---
RESAMPLE_STEP = 0.02     # spatial interval for resampling (in normalized coords)
MAX_SEQ_LEN = 2048       # max points per sample
MIN_STROKE_POINTS = 2    # discard strokes with fewer points
FEATURE_DIM = 6          # (x, y, dx, dy, dt, pen_state)


def parse_inkml(filepath: str) -> Tuple[List[np.ndarray], str]:
    """Parse inkml file → list of strokes (each Nx3: x,y,t) and normalizedLabel."""
    tree = ET.parse(filepath)
    root = tree.getroot()
    ns = {'ink': 'http://www.w3.org/2003/InkML'}

    label = ''
    for ann in root.findall('ink:annotation', ns):
        if ann.get('type') == 'normalizedLabel':
            label = ann.text or ''
            break

    strokes = []
    for trace in root.findall('ink:trace', ns):
        points = []
        for pt_str in trace.text.strip().split(','):
            vals = pt_str.strip().split()
            if len(vals) >= 3:
                points.append([float(vals[0]), float(vals[1]), float(vals[2])])
            elif len(vals) == 2:
                points.append([float(vals[0]), float(vals[1]), 0.0])
        if len(points) >= MIN_STROKE_POINTS:
            strokes.append(np.array(points))

    return strokes, label


def normalize_strokes(strokes: List[np.ndarray]) -> List[np.ndarray]:
    """Scale-normalize strokes. Centers xy at origin, scales to [-1,1]. Normalizes t to [0,1]."""
    if not strokes:
        return strokes

    all_xy = np.concatenate([s[:, :2] for s in strokes], axis=0)
    min_xy = all_xy.min(axis=0)
    max_xy = all_xy.max(axis=0)
    range_xy = max_xy - min_xy
    scale = max(range_xy[0], range_xy[1])
    if scale < 1e-6:
        scale = 1.0
    center = (min_xy + max_xy) / 2.0

    all_t = np.concatenate([s[:, 2] for s in strokes])
    t_min, t_max = all_t.min(), all_t.max()
    t_range = t_max - t_min
    if t_range < 1e-6:
        t_range = 1.0

    normalized = []
    for s in strokes:
        s_new = s.copy()
        s_new[:, :2] = (s[:, :2] - center) / scale
        s_new[:, 2] = (s[:, 2] - t_min) / t_range
        normalized.append(s_new)
    return normalized


def _resample_stroke(stroke: np.ndarray, step: float) -> np.ndarray:
    """Resample a single stroke at fixed spatial intervals.

    Args:
        stroke: Nx3 array (x, y, t)
        step: spatial distance between resampled points

    Returns:
        Mx3 array of resampled (x, y, t) points
    """
    xy = stroke[:, :2]
    t = stroke[:, 2]

    # Cumulative arc length
    diffs = np.diff(xy, axis=0)
    seg_lens = np.sqrt((diffs ** 2).sum(axis=1))
    cum_len = np.zeros(len(xy))
    cum_len[1:] = np.cumsum(seg_lens)
    total_len = cum_len[-1]

    if total_len < 1e-8:
        return stroke[:1].copy()

    # Generate evenly spaced arc-length positions
    n_points = max(2, int(np.ceil(total_len / step)) + 1)
    target_lens = np.linspace(0, total_len, n_points)

    # Interpolate x, y, t at each target arc-length
    resampled = np.zeros((n_points, 3))
    resampled[:, 0] = np.interp(target_lens, cum_len, xy[:, 0])
    resampled[:, 1] = np.interp(target_lens, cum_len, xy[:, 1])
    resampled[:, 2] = np.interp(target_lens, cum_len, t)

    return resampled


def extract_point_features(strokes: List[np.ndarray], step: float = None) -> np.ndarray:
    """Extract point-level features from normalized strokes.

    Resamples each stroke at fixed spatial intervals, then computes per-point:
        0: x position
        1: y position
        2: dx (delta x from previous point)
        3: dy (delta y from previous point)
        4: dt (delta time from previous point, 0 at stroke start)
        5: pen_state (0=pen-down continuation, 1=pen-down start of new stroke)

    Returns: (N, 6) float32 array
    """
    if step is None:
        step = RESAMPLE_STEP

    all_points = []
    for i, stroke in enumerate(strokes):
        resampled = _resample_stroke(stroke, step)
        n = len(resampled)

        features = np.zeros((n, FEATURE_DIM), dtype=np.float32)
        features[:, 0] = resampled[:, 0]  # x
        features[:, 1] = resampled[:, 1]  # y

        # Deltas (first point of each stroke gets 0 deltas)
        if n > 1:
            features[1:, 2] = np.diff(resampled[:, 0])  # dx
            features[1:, 3] = np.diff(resampled[:, 1])  # dy
            features[1:, 4] = np.diff(resampled[:, 2])  # dt

        # Pen state: 1 at start of each new stroke (after pen-up)
        if i > 0:
            features[0, 5] = 1.0

        all_points.append(features)

    if not all_points:
        return np.zeros((0, FEATURE_DIM), dtype=np.float32)

    return np.concatenate(all_points, axis=0)


def process_inkml(filepath: str, resample_step: float = None) -> Tuple[np.ndarray, str]:
    """Full pipeline: inkml → resampled point features (6D).

    Returns:
        (N, 6) feature array and label string
    """
    if resample_step is None:
        resample_step = RESAMPLE_STEP

    strokes, label = parse_inkml(filepath)
    if not strokes:
        return np.zeros((0, FEATURE_DIM), dtype=np.float32), label

    strokes = normalize_strokes(strokes)
    features = extract_point_features(strokes, step=resample_step)

    if len(features) > MAX_SEQ_LEN:
        features = features[:MAX_SEQ_LEN]

    return features, label
