#!/usr/bin/env python3
"""Serve an interactive OCR replay debugger for SupaNotes stroke fixtures.

Run from the repo root:
    python3 prototype/ocr_replay_debug.py

Then open the printed localhost URL. The UI replays recorded fixture strokes,
simulates idle-time OCR triggers, draws line grouping overlays, and shows the
live spatial document model built from the available fixture truth/template file.
"""

from __future__ import annotations

import argparse
import json
import mimetypes
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_FIXTURES_DIR = REPO_ROOT / "prototype" / "fixtures"
TRUTH_FILENAMES = ("truth.json", "truth_template.json", "template.json")

HTML = r"""
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>SupaNotes OCR Replay Debugger</title>
  <style>
    :root {
      color-scheme: light dark;
      --bg: Canvas;
      --fg: CanvasText;
      --muted: color-mix(in srgb, CanvasText 55%, Canvas);
      --panel: color-mix(in srgb, Canvas 92%, CanvasText);
      --border: color-mix(in srgb, CanvasText 20%, Canvas);
      --math: #d43f3a;
      --text: #2f7ee6;
      --pending: #8a8a8a;
      --ink: #101010;
      --paper: #fff;
    }

    * { box-sizing: border-box; }

    body {
      margin: 0;
      padding: 18px;
      font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: var(--bg);
      color: var(--fg);
    }

    h1 {
      margin: 0 0 12px;
      font-size: 20px;
      font-weight: 650;
    }

    .app {
      display: grid;
      grid-template-columns: minmax(320px, 1fr) minmax(300px, 420px);
      gap: 16px;
      align-items: start;
    }

    .toolbar, .panel {
      border: 1px solid var(--border);
      border-radius: 12px;
      background: var(--panel);
      padding: 12px;
    }

    .toolbar {
      display: grid;
      gap: 10px;
      margin-bottom: 12px;
    }

    .row {
      display: flex;
      gap: 10px;
      flex-wrap: wrap;
      align-items: center;
    }

    label {
      display: inline-grid;
      gap: 4px;
      font-size: 12px;
      color: var(--muted);
    }

    select, input, button {
      font: inherit;
    }

    select, input[type="number"] {
      min-height: 34px;
      padding: 4px 8px;
      border: 1px solid var(--border);
      border-radius: 8px;
      background: var(--bg);
      color: var(--fg);
    }

    button {
      min-height: 34px;
      padding: 6px 12px;
      border: 1px solid var(--border);
      border-radius: 8px;
      background: var(--bg);
      color: var(--fg);
      cursor: pointer;
    }

    button.primary {
      background: color-mix(in srgb, Highlight 22%, var(--bg));
      border-color: color-mix(in srgb, Highlight 70%, var(--border));
    }

    input[type="range"] {
      width: 100%;
    }

    .stageWrap {
      width: 100%;
      overflow: auto;
      border: 1px solid var(--border);
      border-radius: 12px;
      background: color-mix(in srgb, var(--bg) 70%, CanvasText);
      padding: 12px;
    }

    canvas {
      display: block;
      width: min(100%, 612px);
      height: auto;
      margin: 0 auto;
      background: var(--paper);
      border-radius: 2px;
      box-shadow: 0 8px 24px rgb(0 0 0 / 16%);
    }

    .status {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 8px;
    }

    .stat {
      border: 1px solid var(--border);
      border-radius: 10px;
      padding: 8px;
      background: var(--bg);
    }

    .stat .label {
      font-size: 11px;
      color: var(--muted);
    }

    .stat .value {
      margin-top: 2px;
      font-variant-numeric: tabular-nums;
      font-weight: 650;
    }

    .side {
      display: grid;
      gap: 12px;
    }

    .panel h2 {
      margin: 0 0 8px;
      font-size: 15px;
      font-weight: 650;
    }

    .legend {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      font-size: 12px;
      color: var(--muted);
    }

    .swatch {
      display: inline-block;
      width: 18px;
      height: 3px;
      vertical-align: middle;
      margin-right: 4px;
      border-radius: 999px;
    }

    .textLine { background: var(--text); }
    .mathLine { background: var(--math); }
    .pendingLine { background: var(--pending); }

    pre {
      margin: 0;
      max-height: 360px;
      overflow: auto;
      white-space: pre-wrap;
      word-break: break-word;
      font-size: 12px;
      line-height: 1.35;
      border: 1px solid var(--border);
      border-radius: 10px;
      padding: 10px;
      background: var(--bg);
    }

    .timelineMarks {
      position: relative;
      height: 18px;
      margin-top: -2px;
    }

    .mark {
      position: absolute;
      top: 0;
      width: 2px;
      height: 14px;
      background: var(--math);
      border-radius: 999px;
    }

    .mark.text { background: var(--text); }

    .callList {
      display: grid;
      gap: 6px;
      font-size: 12px;
    }

    .callItem {
      display: grid;
      grid-template-columns: 56px 1fr auto;
      gap: 8px;
      align-items: baseline;
      border-bottom: 1px solid var(--border);
      padding-bottom: 6px;
    }

    .badge {
      display: inline-block;
      border-radius: 999px;
      padding: 2px 7px;
      border: 1px solid var(--border);
      font-size: 11px;
    }

    .badge.math { color: var(--math); }
    .badge.text { color: var(--text); }

    @media (max-width: 900px) {
      .app { grid-template-columns: 1fr; }
      .status { grid-template-columns: repeat(2, minmax(0, 1fr)); }
    }
  </style>
</head>
<body>
  <h1>SupaNotes OCR Replay Debugger</h1>
  <div class="app">
    <main>
      <section class="toolbar" aria-label="Replay controls">
        <div class="row">
          <label>Fixture
            <select id="fixtureSelect"></select>
          </label>
          <button id="playPause" class="primary" type="button">Play</button>
          <button id="restart" type="button">Restart</button>
          <label>Speed
            <select id="speedSelect">
              <option value="0.25">0.25×</option>
              <option value="0.5">0.5×</option>
              <option value="1" selected>1×</option>
              <option value="2">2×</option>
              <option value="4">4×</option>
            </select>
          </label>
          <label>Idle OCR trigger (sec)
            <input id="idleInput" type="number" min="0.1" max="5" step="0.1" value="0.8" />
          </label>
        </div>
        <div>
          <input id="timeline" type="range" min="0" max="1" step="0.01" value="0" aria-label="Replay timeline" />
          <div id="timelineMarks" class="timelineMarks" aria-hidden="true"></div>
        </div>
        <div class="status">
          <div class="stat"><div class="label">time</div><div id="timeValue" class="value">0.00s</div></div>
          <div class="stat"><div class="label">completed strokes</div><div id="strokeValue" class="value">0</div></div>
          <div class="stat"><div class="label">active groups</div><div id="groupValue" class="value">0</div></div>
          <div class="stat"><div class="label">OCR blocks</div><div id="blockValue" class="value">0</div></div>
        </div>
      </section>
      <div class="stageWrap">
        <canvas id="canvas" width="612" height="792" aria-label="Replayed handwriting canvas"></canvas>
      </div>
    </main>

    <aside class="side">
      <section class="panel">
        <h2>Overlay legend</h2>
        <div class="legend">
          <span><span class="swatch textLine"></span>text line</span>
          <span><span class="swatch mathLine"></span>math line</span>
          <span><span class="swatch pendingLine"></span>group seen, waiting for idle trigger</span>
        </div>
      </section>
      <section class="panel">
        <h2>OCR calls</h2>
        <div id="callList" class="callList"></div>
      </section>
      <section class="panel">
        <h2>Live spatial document model</h2>
        <pre id="modelView">{}</pre>
      </section>
    </aside>
  </div>

  <script>
    const fixtureSelect = document.getElementById('fixtureSelect');
    const playPause = document.getElementById('playPause');
    const restart = document.getElementById('restart');
    const speedSelect = document.getElementById('speedSelect');
    const idleInput = document.getElementById('idleInput');
    const timeline = document.getElementById('timeline');
    const timelineMarks = document.getElementById('timelineMarks');
    const canvas = document.getElementById('canvas');
    const ctx = canvas.getContext('2d');
    const timeValue = document.getElementById('timeValue');
    const strokeValue = document.getElementById('strokeValue');
    const groupValue = document.getElementById('groupValue');
    const blockValue = document.getElementById('blockValue');
    const modelView = document.getElementById('modelView');
    const callList = document.getElementById('callList');

    let fixtures = [];
    let fixture = null;
    let currentTime = 0;
    let duration = 1;
    let playing = false;
    let lastFrame = null;

    const css = getComputedStyle(document.documentElement);
    const colors = {
      paper: css.getPropertyValue('--paper').trim(),
      ink: css.getPropertyValue('--ink').trim(),
      text: css.getPropertyValue('--text').trim(),
      math: css.getPropertyValue('--math').trim(),
      pending: css.getPropertyValue('--pending').trim(),
      muted: css.getPropertyValue('--muted').trim()
    };

    function bboxUnion(a, b) {
      if (!a) return b ? [...b] : null;
      if (!b) return [...a];
      return [Math.min(a[0], b[0]), Math.min(a[1], b[1]), Math.max(a[2], b[2]), Math.max(a[3], b[3])];
    }

    function strokeTimes(stroke) {
      const points = stroke.points || [];
      if (!points.length) return { start: 0, end: 0 };
      return { start: points[0].t || 0, end: points[points.length - 1].t || 0 };
    }

    function normalizeFixture(raw) {
      const truth = raw.truth || { blocks: [], expectedMarkdown: '' };
      const truthByStroke = new Map();
      for (const block of truth.blocks || []) {
        for (const strokeId of block.strokes || []) truthByStroke.set(strokeId, block);
      }
      const strokes = (raw.strokes.strokes || []).map(stroke => ({
        ...stroke,
        times: strokeTimes(stroke),
        truthBlock: truthByStroke.get(stroke.id) || null
      }));
      const canvasInfo = raw.strokes.canvas || { width: 612, height: 792 };
      return { ...raw, strokes: { ...raw.strokes, strokes }, truth, canvasInfo };
    }

    function classifyGroup(group) {
      const truthBlocks = [...new Set(group.strokes.map(stroke => stroke.truthBlock).filter(Boolean))];
      if (truthBlocks.length === 1) {
        const block = truthBlocks[0];
        if (block.kind === 'math' || block.latex) return 'math';
        if (block.kind === 'text' || block.text) return 'text';
      }
      const textish = group.strokes.length > 8 && group.bbox && (group.bbox[2] - group.bbox[0]) > 180;
      return textish ? 'text' : 'math';
    }

    function recognizedContent(group) {
      const truthBlocks = [...new Set(group.strokes.map(stroke => stroke.truthBlock).filter(Boolean))];
      if (truthBlocks.length === 1) {
        const block = truthBlocks[0];
        return block.text || block.latex || '';
      }
      return '';
    }

    function groupCompletedStrokes(completed) {
      const sorted = [...completed].sort((a, b) => (a.bbox?.[1] ?? 0) - (b.bbox?.[1] ?? 0));
      const groups = [];
      for (const stroke of sorted) {
        const bbox = stroke.bbox;
        if (!bbox) continue;
        const centerY = (bbox[1] + bbox[3]) / 2;
        const height = Math.max(1, bbox[3] - bbox[1]);
        let best = null;
        let bestDistance = Infinity;
        for (const group of groups) {
          const threshold = Math.max(34, Math.max(group.height, height) * 1.15);
          const distance = Math.abs(centerY - group.centerY);
          if (distance < threshold && distance < bestDistance) {
            best = group;
            bestDistance = distance;
          }
        }
        if (!best) {
          groups.push({ strokes: [stroke], bbox: [...bbox], centerY, height, lastT: stroke.times.end });
        } else {
          best.strokes.push(stroke);
          best.bbox = bboxUnion(best.bbox, bbox);
          best.centerY = (best.bbox[1] + best.bbox[3]) / 2;
          best.height = Math.max(1, best.bbox[3] - best.bbox[1]);
          best.lastT = Math.max(best.lastT, stroke.times.end);
        }
      }
      return groups
        .map(group => ({ ...group, kind: classifyGroup(group), content: recognizedContent(group) }))
        .sort((a, b) => a.bbox[1] - b.bbox[1] || a.bbox[0] - b.bbox[0]);
    }

    function modelAt(time) {
      if (!fixture) return { completed: [], groups: [], blocks: [] };
      const idleSeconds = Number(idleInput.value) || 0.8;
      const completed = fixture.strokes.strokes.filter(stroke => stroke.times.end <= time);
      const groups = groupCompletedStrokes(completed);
      const blocks = groups
        .filter(group => time >= group.lastT + idleSeconds)
        .map((group, index) => ({
          id: `block_${String(index + 1).padStart(3, '0')}`,
          kind: group.kind,
          bbox: group.bbox.map(value => Math.round(value * 10) / 10),
          strokes: group.strokes.map(stroke => stroke.id),
          text: group.kind === 'text' ? group.content : '',
          latex: group.kind === 'math' ? group.content : '',
          source: group.kind === 'math' ? 'math_ctc' : 'apple_vision_pending',
          recognizedAt: Math.round((group.lastT + idleSeconds) * 100) / 100
        }));
      return { completed, groups, blocks };
    }

    function finalOcrCalls() {
      if (!fixture) return [];
      const idleSeconds = Number(idleInput.value) || 0.8;
      const allGroups = groupCompletedStrokes(fixture.strokes.strokes);
      return allGroups.map((group, index) => ({
        index,
        at: group.lastT + idleSeconds,
        kind: group.kind,
        content: group.content,
        bbox: group.bbox
      })).sort((a, b) => a.at - b.at);
    }

    function setupCanvas() {
      const width = fixture?.canvasInfo?.width || 612;
      const height = fixture?.canvasInfo?.height || 792;
      const ratio = window.devicePixelRatio || 1;
      canvas.width = width * ratio;
      canvas.height = height * ratio;
      canvas.style.aspectRatio = `${width} / ${height}`;
      ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
    }

    function drawStroke(stroke, time) {
      const points = (stroke.points || []).filter(point => point.t <= time);
      if (points.length < 2) return;
      ctx.beginPath();
      ctx.moveTo(points[0].x, points[0].y);
      for (const point of points.slice(1)) ctx.lineTo(point.x, point.y);
      ctx.lineWidth = stroke.width || 3;
      ctx.lineCap = 'round';
      ctx.lineJoin = 'round';
      ctx.strokeStyle = colors.ink;
      ctx.stroke();
    }

    function drawUnderline(group, called) {
      const [x0, y0, x1, y1] = group.bbox;
      const y = y1 + 10;
      ctx.save();
      ctx.lineWidth = 4;
      ctx.lineCap = 'round';
      ctx.strokeStyle = called ? (group.kind === 'math' ? colors.math : colors.text) : colors.pending;
      if (!called) ctx.setLineDash([8, 7]);
      ctx.beginPath();
      ctx.moveTo(x0, y);
      ctx.lineTo(x1, y);
      ctx.stroke();
      ctx.setLineDash([]);
      ctx.font = '12px ui-sans-serif, system-ui';
      ctx.fillStyle = ctx.strokeStyle;
      ctx.fillText(`${group.kind}${called ? ' OCR' : ' pending'}`, x0, y + 17);
      ctx.restore();
    }

    function draw() {
      if (!fixture) return;
      const width = fixture.canvasInfo.width || 612;
      const height = fixture.canvasInfo.height || 792;
      ctx.clearRect(0, 0, width, height);
      ctx.fillStyle = colors.paper;
      ctx.fillRect(0, 0, width, height);

      for (const stroke of fixture.strokes.strokes) {
        if (stroke.times.start <= currentTime) drawStroke(stroke, currentTime);
      }

      const state = modelAt(currentTime);
      const calledKeys = new Set(state.blocks.map(block => block.strokes.join('|')));
      for (const group of state.groups) {
        drawUnderline(group, calledKeys.has(group.strokes.map(stroke => stroke.id).join('|')));
      }

      const documentModel = {
        pageId: fixture.name,
        time: Math.round(currentTime * 100) / 100,
        idleTriggerSeconds: Number(idleInput.value) || 0.8,
        blocks: state.blocks,
        expectedMarkdown: fixture.truth.expectedMarkdown || ''
      };

      timeValue.textContent = `${currentTime.toFixed(2)}s / ${duration.toFixed(2)}s`;
      strokeValue.textContent = `${state.completed.length} / ${fixture.strokes.strokes.length}`;
      groupValue.textContent = String(state.groups.length);
      blockValue.textContent = String(state.blocks.length);
      modelView.textContent = JSON.stringify(documentModel, null, 2);
      renderCalls();
    }

    function renderCalls() {
      const calls = finalOcrCalls();
      callList.innerHTML = '';
      for (const call of calls) {
        const div = document.createElement('div');
        div.className = 'callItem';
        const done = currentTime >= call.at;
        div.style.opacity = done ? '1' : '0.55';
        div.innerHTML = `<span>${call.at.toFixed(2)}s</span><span>${escapeHtml(call.content || '(pending recognizer output)')}</span><span class="badge ${call.kind}">${call.kind}</span>`;
        callList.appendChild(div);
      }
    }

    function renderTimelineMarks() {
      const calls = finalOcrCalls();
      timelineMarks.innerHTML = '';
      for (const call of calls) {
        const mark = document.createElement('span');
        mark.className = `mark ${call.kind}`;
        mark.style.left = `${Math.min(100, Math.max(0, call.at / duration * 100))}%`;
        mark.title = `${call.kind} OCR @ ${call.at.toFixed(2)}s`;
        timelineMarks.appendChild(mark);
      }
    }

    function escapeHtml(value) {
      return String(value).replace(/[&<>'"]/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' }[ch]));
    }

    function setTime(time) {
      currentTime = Math.max(0, Math.min(duration, time));
      timeline.value = String(currentTime);
      draw();
    }

    function tick(timestamp) {
      if (!playing) return;
      if (lastFrame == null) lastFrame = timestamp;
      const elapsed = (timestamp - lastFrame) / 1000 * Number(speedSelect.value);
      lastFrame = timestamp;
      if (currentTime + elapsed >= duration) {
        setTime(duration);
        playing = false;
        playPause.textContent = 'Play';
        lastFrame = null;
        return;
      }
      setTime(currentTime + elapsed);
      requestAnimationFrame(tick);
    }

    async function loadFixture(name) {
      const response = await fetch(`/api/fixture/${encodeURIComponent(name)}`);
      if (!response.ok) throw new Error(await response.text());
      fixture = normalizeFixture(await response.json());
      duration = Math.max(1, ...fixture.strokes.strokes.map(stroke => stroke.times.end)) + 1.5;
      timeline.min = '0';
      timeline.max = String(duration);
      timeline.step = '0.01';
      setupCanvas();
      renderTimelineMarks();
      setTime(0);
    }

    async function init() {
      const response = await fetch('/api/fixtures');
      fixtures = await response.json();
      fixtureSelect.innerHTML = '';
      for (const item of fixtures) {
        const option = document.createElement('option');
        option.value = item.name;
        option.textContent = `${item.name} (${item.strokeCount} strokes)`;
        fixtureSelect.appendChild(option);
      }
      if (fixtures.length) await loadFixture(fixtures[0].name);
    }

    fixtureSelect.addEventListener('change', () => loadFixture(fixtureSelect.value));
    timeline.addEventListener('input', () => {
      playing = false;
      playPause.textContent = 'Play';
      lastFrame = null;
      setTime(Number(timeline.value));
    });
    idleInput.addEventListener('input', () => {
      renderTimelineMarks();
      draw();
    });
    playPause.addEventListener('click', () => {
      playing = !playing;
      playPause.textContent = playing ? 'Pause' : 'Play';
      lastFrame = null;
      if (playing) requestAnimationFrame(tick);
    });
    restart.addEventListener('click', () => {
      playing = false;
      playPause.textContent = 'Play';
      lastFrame = null;
      setTime(0);
    });
    window.addEventListener('resize', draw);

    init().catch(error => {
      modelView.textContent = `Failed to load fixtures: ${error.message}`;
    });
  </script>
</body>
</html>
"""


class ReplayHandler(BaseHTTPRequestHandler):
    fixtures_dir: Path = DEFAULT_FIXTURES_DIR

    def log_message(self, format: str, *args: object) -> None:
        print(f"{self.address_string()} - {format % args}")

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
            self.send_text(HTML, "text/html; charset=utf-8")
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
        if path.startswith("/rendered/") and path.endswith(".png"):
            name = unquote(Path(path).stem)
            try:
                self.send_file(self.fixtures_dir / name / "rendered.png")
            except ValueError as error:
                self.send_json({"error": str(error)}, 404)
            return
        self.send_json({"error": "not found"}, 404)

    def send_file(self, path: Path) -> None:
        resolved = path.resolve()
        if not is_relative_to(resolved, self.fixtures_dir.resolve()) or not resolved.exists():
            raise ValueError("file not found")
        content_type = mimetypes.guess_type(str(resolved))[0] or "application/octet-stream"
        body = resolved.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def is_relative_to(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def truth_path(case_dir: Path) -> Path | None:
    for filename in TRUTH_FILENAMES:
        candidate = case_dir / filename
        if candidate.exists():
            return candidate
    return None


def read_json(path: Path) -> object:
    return json.loads(path.read_text())


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
    if safe_name != name or not is_relative_to(case_dir, fixtures_dir.resolve()):
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


def main() -> None:
    parser = argparse.ArgumentParser(description="Serve the SupaNotes OCR replay debugger.")
    parser.add_argument("--fixtures", type=Path, default=DEFAULT_FIXTURES_DIR)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()

    fixtures_dir = args.fixtures.resolve()
    if not fixtures_dir.exists():
        raise SystemExit(f"Fixtures directory does not exist: {fixtures_dir}")

    ReplayHandler.fixtures_dir = fixtures_dir
    server = ThreadingHTTPServer((args.host, args.port), ReplayHandler)
    print(f"OCR replay debugger: http://{args.host}:{args.port}")
    print(f"Fixtures: {fixtures_dir}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping OCR replay debugger")


if __name__ == "__main__":
    main()
