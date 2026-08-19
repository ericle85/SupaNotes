from PIL import Image, ImageDraw, ImageFont
from placement_utils import compute_equal_sign_center_offset


def test_center_on_equal(suggestion, target_x=400, target_y=150, width=800, height=300):
    img = Image.new("RGB", (width, height), "white")
    draw = ImageDraw.Draw(img)
    fontsize = 48
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", fontsize)
    except OSError:
        font = ImageFont.load_default()

    eq_center_offset = compute_equal_sign_center_offset(
        suggestion, lambda t: draw.textlength(t, font=font)
    )
    text_x = target_x - eq_center_offset
    bbox = draw.textbbox((text_x, target_y), suggestion, font=font, anchor="lm")
    draw.text((text_x, target_y), suggestion, fill=(100, 100, 100, 128), font=font, anchor="lm")

    draw.line([(target_x, 0), (target_x, height)], fill=(200, 200, 200), width=1)
    draw.line([(0, target_y), (width, target_y)], fill=(200, 200, 200), width=1)

    dot_r = 6
    dot_x = target_x
    dot_y = target_y
    draw.ellipse(
        [(dot_x - dot_r, dot_y - dot_r), (dot_x + dot_r, dot_y + dot_r)],
        fill="red",
    )

    draw.text((10, 10), f"suggestion: {suggestion}", fill="black", font=font)

    img.show()
    return img


if __name__ == "__main__":
    test_center_on_equal("=")
    test_center_on_equal("x=5")
    test_center_on_equal("2x+3=11")
