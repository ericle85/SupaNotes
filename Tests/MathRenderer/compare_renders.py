#!/usr/bin/env python3
"""Compare our rendered math images against LaTeX references.

Computes structural similarity (SSIM) and pixel difference for each test case.
Generates side-by-side comparison images and a summary report.
"""
import os
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from skimage.metrics import structural_similarity as ssim
from skimage.transform import resize

SCRIPT_DIR = Path(__file__).parent
OURS_DIR = SCRIPT_DIR / "output_clean"
LATEX_DIR = SCRIPT_DIR / "output_latex"
COMPARE_DIR = SCRIPT_DIR / "output_compare"


def load_and_normalize(path: Path) -> np.ndarray:
    """Load image, convert to grayscale, normalize to [0,1] float."""
    img = Image.open(path).convert("L")
    return np.array(img, dtype=np.float64) / 255.0


def crop_to_content(img: np.ndarray, threshold: float = 0.95) -> np.ndarray:
    """Crop whitespace border around content."""
    mask = img < threshold
    if not mask.any():
        return img
    rows = mask.any(axis=1)
    cols = mask.any(axis=0)
    rmin, rmax = np.where(rows)[0][[0, -1]]
    cmin, cmax = np.where(cols)[0][[0, -1]]
    pad = 5
    rmin = max(0, rmin - pad)
    rmax = min(img.shape[0], rmax + pad + 1)
    cmin = max(0, cmin - pad)
    cmax = min(img.shape[1], cmax + pad + 1)
    return img[rmin:rmax, cmin:cmax]


def match_sizes(ours: np.ndarray, ref: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Resize both images to the same dimensions for comparison."""
    # Resize ours to match ref height, preserving aspect ratio
    scale = ref.shape[0] / ours.shape[0]
    new_w = int(ours.shape[1] * scale)
    ours_resized = resize(ours, (ref.shape[0], new_w), anti_aliasing=True)

    # Pad the narrower image to match widths
    max_w = max(ours_resized.shape[1], ref.shape[1])
    def pad_width(img: np.ndarray, target_w: int) -> np.ndarray:
        if img.shape[1] >= target_w:
            return img[:, :target_w]
        pad = target_w - img.shape[1]
        left = pad // 2
        right = pad - left
        return np.pad(img, ((0, 0), (left, right)), constant_values=1.0)

    return pad_width(ours_resized, max_w), pad_width(ref, max_w)


def compare_case(name: str) -> dict:
    """Compare a single test case. Returns metrics dict."""
    ours_path = OURS_DIR / f"{name}.png"
    ref_path = LATEX_DIR / f"{name}.png"

    ours_raw = load_and_normalize(ours_path)
    ref_raw = load_and_normalize(ref_path)

    ours_crop = crop_to_content(ours_raw)
    ref_crop = crop_to_content(ref_raw)

    ours_matched, ref_matched = match_sizes(ours_crop, ref_crop)

    # SSIM
    score = ssim(ours_matched, ref_matched, data_range=1.0)

    # Mean absolute pixel difference
    mae = np.mean(np.abs(ours_matched - ref_matched))

    # Generate side-by-side comparison
    h = ours_matched.shape[0]
    gap = 10
    combined_w = ours_matched.shape[1] + gap + ref_matched.shape[1]
    combined = np.ones((h + 30, combined_w))  # extra space for label
    combined[:h, :ours_matched.shape[1]] = ours_matched
    combined[:h, ours_matched.shape[1] + gap:] = ref_matched

    # Save comparison
    comp_img = Image.fromarray((combined * 255).astype(np.uint8), mode="L")
    comp_img = comp_img.convert("RGB")
    draw = ImageDraw.Draw(comp_img)
    draw.text((5, h + 5), f"Ours (SSIM={score:.3f})", fill=(0, 0, 200))
    ours_w = ours_matched.shape[1]
    draw.text((ours_w + gap + 5, h + 5), "LaTeX ref", fill=(200, 0, 0))
    comp_img.save(COMPARE_DIR / f"{name}.png")

    return {"name": name, "ssim": score, "mae": mae}


def main() -> None:
    COMPARE_DIR.mkdir(exist_ok=True)

    # Find common test cases
    ours_names = {p.stem for p in OURS_DIR.glob("*.png")}
    ref_names = {p.stem for p in LATEX_DIR.glob("*.png")}
    common = sorted(ours_names & ref_names)

    if not common:
        print("No matching test cases found!")
        sys.exit(1)

    results = []
    for name in common:
        metrics = compare_case(name)
        results.append(metrics)

    # Sort by SSIM (worst first)
    results.sort(key=lambda r: r["ssim"])

    # Print report
    print(f"\n{'Test Case':<30} {'SSIM':>8} {'MAE':>8}")
    print("-" * 50)
    for r in results:
        indicator = "✓" if r["ssim"] > 0.7 else "✗"
        print(f"{indicator} {r['name']:<28} {r['ssim']:>8.3f} {r['mae']:>8.4f}")

    avg_ssim = np.mean([r["ssim"] for r in results])
    print("-" * 50)
    print(f"  {'AVERAGE':<28} {avg_ssim:>8.3f}")
    print(f"\n{len(results)} cases compared → {COMPARE_DIR}/")

    # Worst 5
    print(f"\nWorst 5:")
    for r in results[:5]:
        print(f"  {r['name']}: SSIM={r['ssim']:.3f}")


if __name__ == "__main__":
    main()
