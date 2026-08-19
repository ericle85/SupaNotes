import json
import os
import xml.etree.ElementTree as ET

import matplotlib.patches as patches
import matplotlib.pyplot as plt
import numpy as np


def parse_inkml(path):
    tree = ET.parse(path)
    root = tree.getroot()
    ns = {"ink": "http://www.w3.org/2003/InkML"}

    strokes = []
    for trace in root.findall("ink:trace", ns):
        points = []
        for pt_str in trace.text.strip().split(","):
            vals = pt_str.strip().split()
            if len(vals) >= 2:
                points.append((float(vals[0]), float(vals[1])))
        if len(points) >= 2:
            strokes.append(np.array(points))
    return strokes


def compute_bbox(strokes):
    all_pts = np.concatenate(strokes)
    return {
        "min_x": all_pts[:, 0].min(),
        "max_x": all_pts[:, 0].max(),
        "min_y": all_pts[:, 1].min(),
        "max_y": all_pts[:, 1].max(),
    }


def place_suggestion(bbox, mode):
    gap = 8.0
    line_height = bbox["max_y"] - bbox["min_y"]

    if mode == "append":
        x = bbox["max_x"] + gap
        y = (bbox["min_y"] + bbox["max_y"]) / 2
        return x, y

    if mode == "below":
        x = bbox["min_x"]
        y = bbox["max_y"] + line_height * 0.5
        return x, y

    return None


def visualize(strokes, bbox, placement, suggestion_text, mode):
    fig, ax = plt.subplots(1, 1, figsize=(10, 6))

    for stroke in strokes:
        ax.plot(stroke[:, 0], stroke[:, 1], "k-", linewidth=2)

    rect = patches.Rectangle(
        (bbox["min_x"] - 2, bbox["min_y"] - 2),
        bbox["max_x"] - bbox["min_x"] + 4,
        bbox["max_y"] - bbox["min_y"] + 4,
        linewidth=1,
        edgecolor="blue",
        facecolor="none",
        linestyle="--",
    )
    ax.add_patch(rect)

    if placement:
        px, py = placement
        ax.text(
            px, py, suggestion_text,
            fontsize=14, color="green",
            verticalalignment="center",
            fontweight="bold",
        )
        ax.scatter([px], [py], color="red", s=40, zorder=5)

    ax.set_aspect("equal")
    ax.invert_yaxis()
    ax.set_title(f"Placement: {mode} | Suggestion: '{suggestion_text}'")
    ax.grid(True, alpha=0.3)
    plt.tight_layout()

    out_path = os.path.join(os.path.dirname(args.folder), f"placement_eval.png")
    plt.savefig(out_path, dpi=150)
    plt.show()
    print(f"Saved to {out_path}")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("folder", help="path to exported stroke bundle folder")
    args = parser.parse_args()

    inkml_path = os.path.join(args.folder, "strokes.inkml")
    pipeline_path = os.path.join(args.folder, "pipeline_output.json")

    strokes = parse_inkml(inkml_path)
    bbox = compute_bbox(strokes)

    with open(pipeline_path) as f:
        pipeline = json.load(f)

    mode = pipeline.get("placement", "N/A")
    suggestion = pipeline.get("suggestion", "")
    transcription = pipeline.get("transcription", "")
    classification = pipeline.get("classification", "")

    print(f"Classification: {classification}")
    print(f"Transcription: '{transcription}'")
    print(f"Suggestion: '{suggestion}'")
    print(f"Placement: {mode}")
    print(f"BBox: x=[{bbox['min_x']:.1f}, {bbox['max_x']:.1f}] y=[{bbox['min_y']:.1f}, {bbox['max_y']:.1f}]")

    placement = place_suggestion(bbox, mode)
    if placement:
        print(f"Computed position: x={placement[0]:.1f}, y={placement[1]:.1f}")
    else:
        print(f"No placement computed (mode={mode})")

    visualize(strokes, bbox, placement, suggestion or "?", mode)
