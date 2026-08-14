import pygame
import random
from matplotlib.textpath import TextPath
from matplotlib.font_manager import FontProperties


CANVAS_WIDTH = 800
CANVAS_HEIGHT = 600
BACKGROUND_COLOR = (0, 0, 0)
TARGET_COLOR = (255, 80, 80)
SUGGESTION_COLOR = (80, 255, 80)
POINT_RADIUS = 2
FONT_SIZE = 120
OFFSET_RANGE = 200
POINTS_PER_STROKE = 20


def extract_strokes_from_text(text, font_size):
    font_props = FontProperties(family="Arial")
    text_path = TextPath((0, 0), text, size=font_size, prop=font_props)
    vertices = text_path.vertices
    codes = text_path.codes

    MOVETO = 1
    CLOSEPOLY = 79

    strokes = []
    current_stroke = []

    for vertex, code in zip(vertices, codes):
        if code == MOVETO:
            if len(current_stroke) > 1:
                strokes.append(current_stroke)
            current_stroke = [vertex.tolist()]
        elif code == CLOSEPOLY:
            if len(current_stroke) > 1:
                current_stroke.append(current_stroke[0])
                strokes.append(current_stroke)
            current_stroke = []
        else:
            current_stroke.append(vertex.tolist())

    if len(current_stroke) > 1:
        strokes.append(current_stroke)

    return strokes


def sample_points_along_stroke(stroke, num_points):
    segment_lengths = []
    for i in range(len(stroke) - 1):
        dx = stroke[i + 1][0] - stroke[i][0]
        dy = stroke[i + 1][1] - stroke[i][1]
        segment_lengths.append((dx * dx + dy * dy) ** 0.5)

    total_length = sum(segment_lengths)
    if total_length == 0:
        return [stroke[0]] * num_points

    sampled = []
    step = total_length / (num_points - 1) if num_points > 1 else 0

    accumulated = 0.0
    segment_index = 0
    segment_accumulated = 0.0

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


def flip_y_and_center(strokes, canvas_width, canvas_height):
    all_points = [p for s in strokes for p in s]
    min_x = min(p[0] for p in all_points)
    max_x = max(p[0] for p in all_points)
    min_y = min(p[1] for p in all_points)
    max_y = max(p[1] for p in all_points)

    center_x = (min_x + max_x) / 2
    center_y = (min_y + max_y) / 2

    offset_x = canvas_width / 2 - center_x
    offset_y = canvas_height / 2 + center_y

    centered = []
    for stroke in strokes:
        new_stroke = []
        for x, y in stroke:
            new_stroke.append([x + offset_x, -y + offset_y])
        centered.append(new_stroke)

    return centered


def apply_offset(strokes, dx, dy):
    return [[[x + dx, y + dy] for x, y in stroke] for stroke in strokes]


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

    raw_strokes = extract_strokes_from_text("Hello World", FONT_SIZE)
    base_strokes = flip_y_and_center(raw_strokes, CANVAS_WIDTH, CANVAS_HEIGHT)
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
