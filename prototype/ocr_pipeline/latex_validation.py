"""Does a recognized line parse as math? Shared by the merge guard and re-ranking."""

from __future__ import annotations

from functools import lru_cache


@lru_cache(maxsize=4096)
def latex_parses(text: str) -> bool:
    stripped_text = text.strip()
    if not stripped_text:
        return False
    from autocomplete.ctc_to_autosuggest_translator import translate_ctc_line_to_sympy

    try:
        translate_ctc_line_to_sympy(stripped_text)
    except Exception:
        return False
    return True


def _self_check() -> None:
    assert latex_parses("2x + 3 = 7")
    assert latex_parses(r"\frac{6}{2}")
    assert not latex_parses("")
    assert not latex_parses("2x = 4 = 9")
    assert not latex_parses(r"\begin{matrix} a & b \end{matrix}")
    print("latex_validation self-check passed")


if __name__ == "__main__":
    _self_check()
