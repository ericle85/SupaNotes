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


def find_equal_sign_x_center(strokes):
    horizontal_strokes = []
    for stroke in strokes:
        x_range = stroke[:, 0].max() - stroke[:, 0].min()
        y_range = stroke[:, 1].max() - stroke[:, 1].min()
        if x_range > 3.0 and y_range / (x_range + 0.01) < 0.4:
            mid_x = (stroke[:, 0].min() + stroke[:, 0].max()) / 2
            mid_y = (stroke[:, 1].min() + stroke[:, 1].max()) / 2
            horizontal_strokes.append((mid_x, mid_y, stroke))

    for i in range(len(horizontal_strokes)):
        for j in range(i + 1, len(horizontal_strokes)):
            x1, y1, s1 = horizontal_strokes[i]
            x2, y2, s2 = horizontal_strokes[j]
            x_dist = abs(x1 - x2)
            y_dist = abs(y1 - y2)
            if x_dist < 10.0 and 2.0 < y_dist < 12.0:
                return (x1 + x2) / 2

    return None


def place_suggestion(bbox, mode, strokes=None, transcription="", suggestion=""):
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

    if mode == "alignWithEqualSignAbove":
        equal_x = find_equal_sign_x_center(strokes)
        if equal_x is None:
            return bbox["min_x"], bbox["max_y"] + line_height * 0.5

        y = bbox["max_y"] + line_height * 0.5
        return equal_x, y

    return None


def estimate_stroke_height(strokes):
    heights = []
    for stroke in strokes:
        h = stroke[:, 1].max() - stroke[:, 1].min()
        if h > 1.0:
            heights.append(h)
    if not heights:
        return 20.0
    return float(np.percentile(heights, 40))


def stroke_height_to_fontsize(stroke_height, ax):
    y_min, y_max = ax.get_ylim()
    fig = ax.get_figure()
    fig_height_inches = fig.get_size_inches()[1]
    data_range = abs(y_max - y_min)
    points_per_data_unit = (fig_height_inches * 72.0) / data_range
    return stroke_height * points_per_data_unit


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
        latex_str = f"${suggestion_text}$"
        ghost_color = (0.4, 0.4, 0.4, 0.5)

        ax.set_aspect("equal")
        ax.invert_yaxis()
        ax.autoscale_view()
        fig.canvas.draw()

        fontsize = stroke_height_to_fontsize(estimate_stroke_height(strokes), ax)

        equal_idx = suggestion_text.find("=")
        if mode == "alignWithEqualSignAbove" and equal_idx >= 0:
            prefix = suggestion_text[:equal_idx]
            after_eq = suggestion_text[equal_idx + 1:]
            eq_text = ax.text(
                px, py, "$=$",
                color=ghost_color, verticalalignment="center",
                horizontalalignment="center",
                fontsize=fontsize,
            )
            fig.canvas.draw()
            eq_bb = eq_text.get_window_extent()
            inv = ax.transData.inverted()
            eq_left, _ = inv.transform((eq_bb.x0, eq_bb.y0))
            eq_right, _ = inv.transform((eq_bb.x1, eq_bb.y0))
            if prefix:
                ax.text(
                    eq_left, py, f"${prefix}$",
                    color=ghost_color, verticalalignment="center",
                    horizontalalignment="right",
                    fontsize=fontsize,
                )
            if after_eq:
                ax.text(
                    eq_right, py, f"${after_eq}$",
                    color=ghost_color, verticalalignment="center",
                    horizontalalignment="left",
                    fontsize=fontsize,
                )
        else:
            ax.text(
                px, py, latex_str,
                color=ghost_color, verticalalignment="center",
                fontsize=fontsize,
            )
        ax.scatter([px], [py], color="red", s=40, zorder=5)
    else:
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

    placement = place_suggestion(bbox, mode, strokes=strokes, transcription=transcription, suggestion=suggestion)
    if placement:
        print(f"Computed position: x={placement[0]:.1f}, y={placement[1]:.1f}")
    else:
        print(f"No placement computed (mode={mode})")

    visualize(strokes, bbox, placement, suggestion or "?", mode)
