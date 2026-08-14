import pygame
import random
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from skimage.morphology import skeletonize
from collections import deque


CANVAS_WIDTH = 800
CANVAS_HEIGHT = 600
BACKGROUND_COLOR = (0, 0, 0)
TARGET_COLOR = (255, 80, 80)
SUGGESTION_COLOR = (80, 255, 80)
POINT_RADIUS = 2
OFFSET_RANGE = 200
POINTS_PER_STROKE = 20
RENDER_FONT_SIZE = 200
DISPLAY_SCALE = 0.5
SIMPLIFY_TOLERANCE = 1.5


def render_text_to_skeleton(text, font_size):
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", font_size)
    except OSError:
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", font_size)

    bbox = font.getbbox(text)
    padding = 20
    width = bbox[2] - bbox[0] + padding * 2
    height = bbox[3] - bbox[1] + padding * 2

    img = Image.new("L", (width, height), 0)
    draw = ImageDraw.Draw(img)
    draw.text((padding - bbox[0], padding - bbox[1]), text, fill=255, font=font)

    binary = np.array(img) > 128
    skeleton = skeletonize(binary)
    return skeleton


def find_neighbors(skeleton, y, x):
    neighbors = []
    for dy in [-1, 0, 1]:
        for dx in [-1, 0, 1]:
            if dy == 0 and dx == 0:
                continue
            ny = y + dy
            nx = x + dx
            if 0 <= ny < skeleton.shape[0] and 0 <= nx < skeleton.shape[1]:
                if skeleton[ny, nx]:
                    neighbors.append((ny, nx))
    return neighbors


def trace_skeleton_to_strokes(skeleton):
    visited = np.zeros_like(skeleton, dtype=bool)
    neighbor_count = np.zeros_like(skeleton, dtype=int)

    ys, xs = np.where(skeleton)
    for y, x in zip(ys, xs):
        neighbor_count[y, x] = len(find_neighbors(skeleton, y, x))

    endpoints = set()
    junctions = set()
    for y, x in zip(ys, xs):
        count = neighbor_count[y, x]
        if count == 1:
            endpoints.add((y, x))
        elif count >= 3:
            junctions.add((y, x))

    strokes = []

    start_points = list(endpoints)
    for y, x in zip(ys, xs):
        if (y, x) not in endpoints and not visited[y, x]:
            start_points.append((y, x))

    for start_y, start_x in start_points:
        if visited[start_y, start_x]:
            continue

        stroke = [(start_x, start_y)]
        visited[start_y, start_x] = True
        current = (start_y, start_x)

        while True:
            neighbors = find_neighbors(skeleton, current[0], current[1])
            unvisited = [(ny, nx) for ny, nx in neighbors if not visited[ny, nx]]

            if len(unvisited) == 0:
                break

            next_point = unvisited[0]
            visited[next_point[0], next_point[1]] = True
            stroke.append((next_point[1], next_point[0]))
            current = next_point

            if current in junctions or current in endpoints:
                break

        if len(stroke) >= 2:
            strokes.append(stroke)

    return strokes


def simplify_stroke(stroke, tolerance):
    if len(stroke) <= 2:
        return stroke

    start = stroke[0]
    end = stroke[-1]
    max_dist = 0
    max_idx = 0

    dx = end[0] - start[0]
    dy = end[1] - start[1]
    line_len = (dx * dx + dy * dy) ** 0.5

    for i in range(1, len(stroke) - 1):
        if line_len == 0:
            dist = ((stroke[i][0] - start[0]) ** 2 + (stroke[i][1] - start[1]) ** 2) ** 0.5
        else:
            dist = abs(dy * stroke[i][0] - dx * stroke[i][1] + end[0] * start[1] - end[1] * start[0]) / line_len

        if dist > max_dist:
            max_dist = dist
            max_idx = i

    if max_dist > tolerance:
        left = simplify_stroke(stroke[:max_idx + 1], tolerance)
        right = simplify_stroke(stroke[max_idx:], tolerance)
        return left[:-1] + right

    return [start, end]


def build_strokes_from_arial(text):
    skeleton = render_text_to_skeleton(text, RENDER_FONT_SIZE)
    raw_strokes = trace_skeleton_to_strokes(skeleton)

    scaled = []
    for stroke in raw_strokes:
        simplified = simplify_stroke(stroke, SIMPLIFY_TOLERANCE)
        scaled_stroke = [[x * DISPLAY_SCALE, y * DISPLAY_SCALE] for x, y in simplified]
        scaled.append(scaled_stroke)

    return scaled


def center_strokes(strokes, canvas_width, canvas_height):
    all_points = [p for s in strokes for p in s]
    min_x = min(p[0] for p in all_points)
    max_x = max(p[0] for p in all_points)
    min_y = min(p[1] for p in all_points)
    max_y = max(p[1] for p in all_points)

    offset_x = canvas_width / 2 - (min_x + max_x) / 2
    offset_y = canvas_height / 2 - (min_y + max_y) / 2

    return [[[x + offset_x, y + offset_y] for x, y in stroke] for stroke in strokes]


def apply_offset(strokes, dx, dy):
    return [[[x + dx, y + dy] for x, y in stroke] for stroke in strokes]


def sample_points_along_stroke(stroke, num_points):
    segment_lengths = []
    for i in range(len(stroke) - 1):
        dx = stroke[i + 1][0] - stroke[i][0]
        dy = stroke[i + 1][1] - stroke[i][1]
        segment_lengths.append((dx * dx + dy * dy) ** 0.5)

    total_length = sum(segment_lengths)
    if total_length == 0:
        return [stroke[0]] * num_points

    step = total_length / (num_points - 1) if num_points > 1 else 0
    sampled = []
    accumulated = 0.0
    segment_index = 0

    for i in range(num_points):
        target_dist = i * step

        while segment_index < len(segment_lengths) - 1 and accumulated + segment_lengths[segment_index] < target_dist:
            accumulated += segment_lengths[segment_index]
            segment_index += 1

        remaining = target_dist - accumulated
        seg_len = segment_lengths[segment_index]
        t = remaining / seg_len if seg_len > 0 else 0
        t = max(0, min(1, t))

        x = stroke[segment_index][0] + t * (stroke[segment_index + 1][0] - stroke[segment_index][0])
        y = stroke[segment_index][1] + t * (stroke[segment_index + 1][1] - stroke[segment_index][1])
        sampled.append([x, y])

    return sampled


def sample_all_strokes(strokes, points_per_stroke):
    return [sample_points_along_stroke(s, points_per_stroke) for s in strokes]


def draw_strokes(surface, strokes, color):
    for stroke in strokes:
        if len(stroke) < 2:
            continue
        points = [(int(x), int(y)) for x, y in stroke]
        pygame.draw.lines(surface, color, False, points, 2)
        for point in points:
            pygame.draw.circle(surface, color, point, POINT_RADIUS)


def random_offset():
    return (
        random.uniform(-OFFSET_RANGE, OFFSET_RANGE),
        random.uniform(-OFFSET_RANGE, OFFSET_RANGE),
    )


def run():
    pygame.init()
    screen = pygame.display.set_mode((CANVAS_WIDTH, CANVAS_HEIGHT))
    pygame.display.set_caption("AutoPlace Env — drag green to overlap red")
    clock = pygame.time.Clock()

    raw_strokes = build_strokes_from_arial("Hello World")
    base_strokes = center_strokes(raw_strokes, CANVAS_WIDTH, CANVAS_HEIGHT)
    sampled_strokes = sample_all_strokes(base_strokes, POINTS_PER_STROKE)

    target_dx, target_dy = random_offset()
    target_strokes = apply_offset(sampled_strokes, target_dx, target_dy)

    suggestion_dx = 0.0
    suggestion_dy = 0.0

    dragging = False
    last_mouse_pos = None

    running = True
    while running:
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False

            if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
                dragging = True
                last_mouse_pos = event.pos

            if event.type == pygame.MOUSEBUTTONUP and event.button == 1:
                dragging = False
                last_mouse_pos = None

            if event.type == pygame.MOUSEMOTION and dragging:
                mx, my = event.pos
                if last_mouse_pos is not None:
                    suggestion_dx += mx - last_mouse_pos[0]
                    suggestion_dy += my - last_mouse_pos[1]
                last_mouse_pos = event.pos

            if event.type == pygame.KEYDOWN and event.key == pygame.K_r:
                target_dx, target_dy = random_offset()
                target_strokes = apply_offset(sampled_strokes, target_dx, target_dy)
                suggestion_dx = 0.0
                suggestion_dy = 0.0

        suggestion_strokes = apply_offset(sampled_strokes, suggestion_dx, suggestion_dy)

        screen.fill(BACKGROUND_COLOR)
        draw_strokes(screen, target_strokes, TARGET_COLOR)
        draw_strokes(screen, suggestion_strokes, SUGGESTION_COLOR)

        font = pygame.font.SysFont("monospace", 14)
        distance = ((suggestion_dx - target_dx) ** 2 + (suggestion_dy - target_dy) ** 2) ** 0.5
        info = font.render(f"dist: {distance:.1f}  |  R to reset  |  drag green to target", True, (180, 180, 180))
        screen.blit(info, (10, CANVAS_HEIGHT - 25))

        pygame.display.flip()
        clock.tick(60)

    pygame.quit()


if __name__ == "__main__":
    run()
