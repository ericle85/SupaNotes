import json
import os
import xml.etree.ElementTree as ET

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from placement_utils import compute_equal_sign_center_offset


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
    return float(np.percentile(heights, 50))


def strokes_to_image_coords(strokes, bbox, margin, scale):
    shifted = []
    for stroke in strokes:
        xs = (stroke[:, 0] - bbox["min_x"] + margin) * scale
        ys = (stroke[:, 1] - bbox["min_y"] + margin) * scale
        shifted.append(np.column_stack([xs, ys]))
    return shifted


def visualize(strokes, bbox, placement, suggestion_text, mode):
    margin = 20.0
    data_w = bbox["max_x"] - bbox["min_x"] + 2 * margin
    data_h = bbox["max_y"] - bbox["min_y"] + 2 * margin

    scale = 8.0
    img_w = int(data_w * scale)
    img_h = int(data_h * scale * 1.8)

    img = Image.new("RGB", (img_w, img_h), "white")
    draw = ImageDraw.Draw(img)

    img_strokes = strokes_to_image_coords(strokes, bbox, margin, scale)
    for s in img_strokes:
        pts = [(x, y) for x, y in s]
        if len(pts) >= 2:
            draw.line(pts, fill="black", width=3)

    stroke_h = estimate_stroke_height(strokes)
    fontsize = max(12, int(stroke_h * scale * 0.8))
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", fontsize)
    except OSError:
        font = ImageFont.load_default()

    ghost_color = (120, 120, 120)

    if placement:
        px_data, py_data = placement
        px_img = (px_data - bbox["min_x"] + margin) * scale
        py_img = (py_data - bbox["min_y"] + margin) * scale

        equal_idx = suggestion_text.find("=")
        if mode == "alignWithEqualSignAbove" and equal_idx >= 0:
            eq_offset = compute_equal_sign_center_offset(
                suggestion_text, lambda t: draw.textlength(t, font=font)
            )
            text_x = px_img - eq_offset
            draw.text((text_x, py_img), suggestion_text, fill=ghost_color, font=font, anchor="lm")
        else:
            draw.text((px_img, py_img), suggestion_text, fill=ghost_color, font=font, anchor="lm")

        dot_r = 5
        draw.ellipse(
            [(px_img - dot_r, py_img - dot_r), (px_img + dot_r, py_img + dot_r)],
            fill="red",
        )

    bb_x0 = margin * scale - 2
    bb_y0 = margin * scale - 2
    bb_x1 = (bbox["max_x"] - bbox["min_x"] + margin) * scale + 2
    bb_y1 = (bbox["max_y"] - bbox["min_y"] + margin) * scale + 2
    draw.rectangle([bb_x0, bb_y0, bb_x1, bb_y1], outline="blue", width=1)

    title = f"Placement: {mode} | Suggestion: '{suggestion_text}'"
    try:
        title_font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 16)
    except OSError:
        title_font = ImageFont.load_default()
    draw.text((10, 10), title, fill="black", font=title_font)

    out_path = os.path.join(os.path.dirname(args.folder), "placement_eval.png")
    img.save(out_path)
    img.show()
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
