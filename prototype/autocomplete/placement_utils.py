def compute_equal_sign_center_offset(text, measure_fn):
    equal_idx = text.find("=")
    if equal_idx < 0:
        return 0.0

    prefix = text[:equal_idx]
    prefix_eq = text[: equal_idx + 1]

    prefix_w = measure_fn(prefix) if prefix else 0.0
    prefix_eq_w = measure_fn(prefix_eq)
    eq_char_w = prefix_eq_w - prefix_w

    return prefix_w + eq_char_w / 2
