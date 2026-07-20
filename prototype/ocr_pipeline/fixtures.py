"""Fixture loading for SupaNotes OCR replay/debug tooling."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

TRUTH_FILENAMES = ("truth.json", "template.json", "truth_template.json")


def is_relative_to(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def read_json(path: Path) -> Any:
    return json.loads(path.read_text())


def truth_path(case_dir: Path) -> Path | None:
    for filename in TRUTH_FILENAMES:
        candidate = case_dir / filename
        if candidate.exists():
            return candidate
    return None


def list_fixtures(fixtures_dir: Path) -> list[dict[str, object]]:
    items: list[dict[str, object]] = []
    for case_dir in sorted(fixtures_dir.glob("case_*")):
        strokes_path = case_dir / "strokes.json"
        if not case_dir.is_dir() or not strokes_path.exists():
            continue
        strokes = read_json(strokes_path)
        stroke_items = strokes.get("strokes", []) if isinstance(strokes, dict) else []
        items.append(
            {
                "name": case_dir.name,
                "strokeCount": len(stroke_items),
                "hasTruth": truth_path(case_dir) is not None,
            }
        )
    return items


def load_fixture(fixtures_dir: Path, name: str) -> dict[str, object]:
    safe_name = Path(name).name
    case_dir = (fixtures_dir / safe_name).resolve()
    fixtures_root = fixtures_dir.resolve()
    if safe_name != name or not is_relative_to(case_dir, fixtures_root):
        raise ValueError("invalid fixture name")

    strokes_path = case_dir / "strokes.json"
    if not strokes_path.exists():
        raise ValueError("fixture not found")

    template_path = truth_path(case_dir)
    truth = read_json(template_path) if template_path else {"blocks": [], "expectedMarkdown": ""}
    return {
        "name": safe_name,
        "strokes": read_json(strokes_path),
        "truth": truth,
        "truthFile": template_path.name if template_path else None,
    }
