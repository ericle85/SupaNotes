#!/usr/bin/env python3
"""Run one fixture through OCR + autosuggest headless and print the result."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from ocr_pipeline import build_replay_state, load_fixture
from ocr_pipeline.recognizer import load_recognizer

FIXTURES_DIR = Path(__file__).resolve().parent / "fixtures"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixture", nargs="?", default="case_20260723_054027")
    parser.add_argument("--idle", type=float, default=0.8)
    args = parser.parse_args()

    load_recognizer()
    fixture = load_fixture(FIXTURES_DIR, args.fixture)
    state = build_replay_state(fixture, 1e9, args.idle)

    for block in state["blocks"]:
        print(json.dumps({
            "block": block["id"],
            "kind": block["kind"],
            "latex": block["latex"],
            "text": block["text"],
            "autocomplete": block["autocomplete"],
        }, indent=2))


if __name__ == "__main__":
    main()
