#!/usr/bin/env python3
"""Serve an interactive OCR replay debugger for SupaNotes stroke fixtures.

Build the TypeScript frontend once, then run from the repo root:
    (cd prototype/frontend && npm install && npm run build)
    python3 prototype/ocr_replay_debug.py

Then open the printed localhost URL. The UI replays recorded fixture strokes,
simulates idle-time OCR triggers, draws line grouping overlays, and shows the
live spatial document model built from the fixture.
"""

from __future__ import annotations

import argparse
import json
import mimetypes
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlparse

from ocr_pipeline.fixtures import is_relative_to, list_fixtures, load_fixture
from ocr_pipeline.recognizer import load_recognizer
from ocr_pipeline.replay import build_replay_state, clear_recognition_cache

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_FIXTURES_DIR = REPO_ROOT / "prototype" / "fixtures"
FRONTEND_DIR = Path(__file__).resolve().parent / "frontend"


class ReplayHandler(BaseHTTPRequestHandler):
    fixtures_dir: Path = DEFAULT_FIXTURES_DIR

    def log_message(self, format: str, *args: object) -> None:
        # print(f"{self.address_string()} - {format % args}")
        pass

    def send_json(self, payload: object, status: int = 200) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_text(self, text: str, content_type: str = "text/plain; charset=utf-8", status: int = 200) -> None:
        body = text.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        path = parsed.path
        if path == "/":
            self.serve_frontend("index.html")
            return
        if path == "/api/fixtures":
            self.send_json(list_fixtures(self.fixtures_dir))
            return
        if path.startswith("/api/fixture/"):
            name = unquote(path.removeprefix("/api/fixture/"))
            try:
                self.send_json(load_fixture(self.fixtures_dir, name))
            except ValueError as error:
                self.send_json({"error": str(error)}, 404)
            return
        if path.startswith("/api/replay_state/"):
            name = unquote(path.removeprefix("/api/replay_state/"))
            query = parse_qs(parsed.query)
            time_seconds = parse_float(query.get("time", ["0"])[0], default=0.0)
            idle_seconds = parse_float(query.get("idle", ["0.8"])[0], default=0.8)
            try:
                if query.get("reset", [""])[0] in {"1", "true", "yes"}:
                    clear_recognition_cache()
                fixture = load_fixture(self.fixtures_dir, name)
                self.send_json(build_replay_state(fixture, time_seconds, idle_seconds))
            except ValueError as error:
                self.send_json({"error": str(error)}, 404)
            return
        if path.startswith("/rendered/") and path.endswith(".png"):
            name = unquote(Path(path).stem)
            try:
                self.send_file(self.fixtures_dir / name / "rendered.png", self.fixtures_dir)
            except ValueError as error:
                self.send_json({"error": str(error)}, 404)
            return
        self.serve_frontend(path.lstrip("/"))

    def do_POST(self) -> None:  # noqa: N802
        self.send_json({"error": "not found"}, 404)

    def serve_frontend(self, relative: str) -> None:
        try:
            self.send_file(FRONTEND_DIR / relative, FRONTEND_DIR)
        except ValueError:
            self.send_json({"error": "not found"}, 404)

    def send_file(self, path: Path, base: Path) -> None:
        resolved = path.resolve()
        if not is_relative_to(resolved, base.resolve()) or not resolved.is_file():
            raise ValueError("file not found")
        content_type = mimetypes.guess_type(str(resolved))[0] or "application/octet-stream"
        body = resolved.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def parse_float(value: str, default: float) -> float:
    try:
        return float(value)
    except ValueError:
        return default


def main() -> None:
    parser = argparse.ArgumentParser(description="Serve the OCR replay debugger.")
    parser.add_argument("--fixtures", type=Path, default=DEFAULT_FIXTURES_DIR)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()

    fixtures_dir = args.fixtures.resolve()
    if not fixtures_dir.exists():
        raise SystemExit(f"Fixtures directory does not exist: {fixtures_dir}")
    if not (FRONTEND_DIR / "app.js").is_file():
        raise SystemExit(
            f"Frontend not built. Run: (cd {FRONTEND_DIR} && npm install && npm run build)"
        )

    load_recognizer()
    print("OCR model weights loaded.")
    ReplayHandler.fixtures_dir = fixtures_dir
    server = HTTPServer((args.host, args.port), ReplayHandler)
    print(f"OCR replay debugger: http://{args.host}:{args.port}")
    print(f"Fixtures: {fixtures_dir}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping OCR replay debugger")


if __name__ == "__main__":
    main()
