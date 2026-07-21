type Kind = "math" | "text";

interface StrokePoint {
  x: number;
  y: number;
  t: number;
}

interface StrokeTimes {
  start: number;
  end: number;
}

interface RawStroke {
  id: string;
  points?: StrokePoint[];
  width?: number;
}

interface DrawStroke extends RawStroke {
  times: StrokeTimes;
}

interface CanvasInfo {
  width: number;
  height: number;
}

interface RawFixture {
  strokes: { strokes?: RawStroke[]; canvas?: CanvasInfo };
}

interface Fixture {
  strokes: { strokes: DrawStroke[]; canvas?: CanvasInfo };
  canvasInfo: CanvasInfo;
}

interface FixtureListItem {
  name: string;
  strokeCount: number;
}

type Bbox = [number, number, number, number];

interface TokenConfidence {
  token: string;
  confidence: number;
  alternatives: { token: string; confidence: number }[];
}

interface Group {
  kind: Kind;
  content: string;
  confidence: number;
  tokens: TokenConfidence[];
  bbox: Bbox;
  lastT: number;
  lastPenContactT: number;
  strokes: string[];
}

interface Autocomplete {
  operation: string;
  suggestion: string;
  reason: string;
}

interface Block {
  strokes: string[];
  kind: Kind;
  latex?: string;
  text?: string;
  autocomplete?: Autocomplete | null;
}

interface OcrCall {
  at: number;
  kind: Kind;
  content: string;
}

interface GapGuide {
  x: number;
  y0: number;
  y1: number;
  gap: number;
  isSplit: boolean;
}

interface ReplayState {
  completedStrokeCount: number;
  totalStrokeCount: number;
  groups: Group[];
  blocks: Block[];
  calls: OcrCall[];
  gapGuides?: GapGuide[];
  document: unknown;
}

interface ClassifiedUnderline {
  x0: number;
  x1: number;
  y: number;
  kind: Kind;
  content: string;
  confidence: number;
  tokens: TokenConfidence[];
  autocomplete?: Autocomplete | null;
  latex?: string | null;
}

const byId = <T extends HTMLElement>(id: string): T =>
  document.getElementById(id) as T;

const fixtureSelect = byId<HTMLSelectElement>("fixtureSelect");
const playPause = byId<HTMLButtonElement>("playPause");
const restart = byId<HTMLButtonElement>("restart");
const speedSelect = byId<HTMLSelectElement>("speedSelect");
const idleInput = byId<HTMLInputElement>("idleInput");
const gapInput = byId<HTMLInputElement>("gapInput");
const gapValue = byId<HTMLSpanElement>("gapValue");
const timeline = byId<HTMLInputElement>("timeline");
const timelineMarks = byId<HTMLDivElement>("timelineMarks");
const canvas = byId<HTMLCanvasElement>("canvas");
const ctx = canvas.getContext("2d") as CanvasRenderingContext2D;
const timeValue = byId<HTMLDivElement>("timeValue");
const strokeValue = byId<HTMLDivElement>("strokeValue");
const groupValue = byId<HTMLDivElement>("groupValue");
const blockValue = byId<HTMLDivElement>("blockValue");
const modelView = byId<HTMLPreElement>("modelView");
const callList = byId<HTMLDivElement>("callList");
const autocompleteList = byId<HTMLDivElement>("autocompleteList");
const ocrTooltip = byId<HTMLDivElement>("ocrTooltip");

let classifiedUnderlines: ClassifiedUnderline[] = [];

let fixtures: FixtureListItem[] = [];
let fixture: Fixture | null = null;
let currentTime = 0;
let duration = 1;
let playing = false;
let lastFrame: number | null = null;

const css = getComputedStyle(document.documentElement);
const colors = {
  paper: css.getPropertyValue("--paper").trim(),
  ink: css.getPropertyValue("--ink").trim(),
  text: css.getPropertyValue("--text").trim(),
  math: css.getPropertyValue("--math").trim(),
  pending: css.getPropertyValue("--pending").trim(),
  muted: css.getPropertyValue("--muted").trim(),
};

let replayState: ReplayState = {
  completedStrokeCount: 0,
  totalStrokeCount: 0,
  groups: [],
  blocks: [],
  calls: [],
  document: {},
};
let stateRequestSerial = 0;

const strokeTimes = (stroke: RawStroke): StrokeTimes => {
  const points = stroke.points || [];
  if (!points.length) return { start: 0, end: 0 };
  return { start: points[0].t || 0, end: points[points.length - 1].t || 0 };
};

const prepareFixtureForDrawing = (raw: RawFixture): Fixture => {
  const strokes = (raw.strokes.strokes || []).map((stroke) => ({
    ...stroke,
    times: strokeTimes(stroke),
  }));
  const canvasInfo = raw.strokes.canvas || { width: 612, height: 792 };
  return { ...raw, strokes: { ...raw.strokes, strokes }, canvasInfo };
};

const kindColor = (kind: Kind): string =>
  ({ math: colors.math, text: colors.text } as Record<Kind, string>)[kind] ||
  colors.pending;

async function fetchReplayState(time: number): Promise<void> {
  if (!fixture) return;
  const serial = ++stateRequestSerial;
  const idleSeconds = Number(idleInput.value) || 0.8;
  const gap = Number(gapInput.value) || 46;
  const name = fixtures.find((item) => item.name === fixtureSelect.value)?.name ?? fixtureSelect.value;
  const url = `/api/replay_state/${encodeURIComponent(name)}?time=${encodeURIComponent(time.toFixed(3))}&idle=${encodeURIComponent(idleSeconds)}&gap=${encodeURIComponent(gap)}`;
  const response = await fetch(url);
  if (!response.ok) throw new Error(await response.text());
  const nextState = (await response.json()) as ReplayState;
  if (serial === stateRequestSerial) {
    replayState = nextState;
    renderTimelineMarks();
    draw();
  }
}

const setupCanvas = (): void => {
  const width = fixture?.canvasInfo?.width || 612;
  const height = fixture?.canvasInfo?.height || 792;
  const ratio = window.devicePixelRatio || 1;
  canvas.width = width * ratio;
  canvas.height = height * ratio;
  canvas.style.aspectRatio = `${width} / ${height}`;
  ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
};

const drawStroke = (stroke: DrawStroke, time: number): void => {
  const points = (stroke.points || []).filter((point) => point.t <= time);
  if (points.length < 2) return;
  ctx.beginPath();
  ctx.moveTo(points[0].x, points[0].y);
  for (const point of points.slice(1)) ctx.lineTo(point.x, point.y);
  ctx.lineWidth = stroke.width || 3;
  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  ctx.strokeStyle = colors.ink;
  ctx.stroke();
};

const drawUnderline = (group: Group, called: boolean): void => {
  const [x0, , x1, y1] = group.bbox;
  const y = y1 + 10;
  ctx.save();
  ctx.lineWidth = 4;
  ctx.lineCap = "round";
  const classified = called && (group.kind === "math" || group.kind === "text");
  ctx.strokeStyle = called ? kindColor(group.kind) : colors.pending;
  if (!called) ctx.setLineDash([8, 7]);
  ctx.beginPath();
  ctx.moveTo(x0, y);
  ctx.lineTo(x1, y);
  ctx.stroke();
  ctx.setLineDash([]);
  const idle = Number(idleInput.value) || 0.8;
  const remaining = Math.max(0, group.lastPenContactT + idle - currentTime);
  ctx.font = "12px ui-sans-serif, system-ui";
  ctx.fillStyle = ctx.strokeStyle;
  ctx.fillText(
    called ? `${group.kind} OCR` : `${group.kind} pending ${remaining.toFixed(1)}s`,
    x0,
    y + 17
  );
  if (!called && idle > 0) {
    const progress = Math.max(0, Math.min(1, 1 - remaining / idle));
    ctx.strokeStyle = colors.pending;
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(x0, y + 22);
    ctx.lineTo(x0 + (x1 - x0) * progress, y + 22);
    ctx.stroke();
  }
  ctx.restore();
  if (classified) {
    const key = group.strokes.join("|");
    const block = replayState.blocks.find((candidate) => candidate.strokes.join("|") === key);
    classifiedUnderlines.push({
      x0,
      x1,
      y,
      kind: group.kind,
      content: group.content,
      confidence: group.confidence,
      tokens: group.tokens ?? [],
      autocomplete: block?.autocomplete ?? null,
      latex: block?.latex ?? null,
    });
  }
};

const drawGapGauge = (threshold: number): void => {
  const y = 14;
  const x0 = 12;
  const x1 = x0 + threshold;
  ctx.save();
  ctx.strokeStyle = colors.math;
  ctx.fillStyle = colors.math;
  ctx.lineWidth = 1.5;
  ctx.setLineDash([]);
  ctx.beginPath(); ctx.moveTo(x0, y - 7); ctx.lineTo(x0, y + 7); ctx.stroke();
  ctx.beginPath(); ctx.moveTo(x1, y - 7); ctx.lineTo(x1, y + 7); ctx.stroke();
  ctx.beginPath(); ctx.moveTo(x0, y); ctx.lineTo(x1, y); ctx.stroke();
  ctx.font = "11px ui-sans-serif, system-ui";
  ctx.fillText(`split gap ${threshold}px`, x1 + 6, y + 4);
  ctx.restore();
};

const drawSplitGuides = (): void => {
  const threshold = Number(gapInput.value) || 46;
  const guides = replayState.gapGuides || [];
  ctx.save();
  ctx.font = "10px ui-sans-serif, system-ui";
  for (const guide of guides) {
    const top = guide.y0 - 6;
    const bottom = guide.y1 + 6;
    ctx.strokeStyle = guide.isSplit ? colors.math : colors.muted;
    ctx.lineWidth = guide.isSplit ? 2 : 1;
    ctx.setLineDash(guide.isSplit ? [] : [3, 4]);
    ctx.beginPath();
    ctx.moveTo(guide.x, top);
    ctx.lineTo(guide.x, bottom);
    ctx.stroke();
    if (guide.isSplit || guide.gap >= 8) {
      ctx.setLineDash([]);
      ctx.fillStyle = guide.isSplit ? colors.math : colors.muted;
      ctx.fillText(`${guide.gap.toFixed(0)}px`, guide.x + 2, top + 10);
    }
  }
  ctx.setLineDash([]);
  ctx.restore();
  drawGapGauge(threshold);
};

const draw = (): void => {
  if (!fixture) return;
  const width = fixture.canvasInfo.width || 612;
  const height = fixture.canvasInfo.height || 792;
  ctx.clearRect(0, 0, width, height);
  ctx.fillStyle = colors.paper;
  ctx.fillRect(0, 0, width, height);

  for (const stroke of fixture.strokes.strokes) {
    if (stroke.times.start <= currentTime) drawStroke(stroke, currentTime);
  }

  classifiedUnderlines = [];
  const calledKeys = new Set(replayState.blocks.map((block) => block.strokes.join("|")));
  for (const group of replayState.groups) {
    drawUnderline(group, calledKeys.has(group.strokes.join("|")));
  }
  drawSplitGuides();

  timeValue.textContent = `${currentTime.toFixed(2)}s / ${duration.toFixed(2)}s`;
  strokeValue.textContent = `${replayState.completedStrokeCount} / ${replayState.totalStrokeCount}`;
  groupValue.textContent = String(replayState.groups.length);
  blockValue.textContent = String(replayState.blocks.length);
  modelView.textContent = JSON.stringify(replayState.document, null, 2);
  renderCalls();
  renderAutocomplete();
};

const renderAutocomplete = (): void => {
  const mathBlocks = replayState.blocks.filter((block) => block.kind === "math");
  autocompleteList.innerHTML = "";
  if (!mathBlocks.length) {
    autocompleteList.innerHTML = `<div class="callItem" style="opacity:0.55"><span>no recognized math yet</span></div>`;
    return;
  }
  for (const block of mathBlocks) {
    const auto = block.autocomplete;
    const suggestion = auto?.suggestion
      ? escapeHtml(auto.suggestion)
      : `<span style="opacity:0.55">${escapeHtml(auto?.reason || "no suggestion")}</span>`;
    const div = document.createElement("div");
    div.className = "callItem";
    const rendered = block.latex ? renderLatex(block.latex) : "";
    div.innerHTML = `<span>${rendered}</span><span>→ ${suggestion}</span><span class="badge math">${escapeHtml(auto?.operation || "")}</span>`;
    autocompleteList.appendChild(div);
  }
};

const renderCalls = (): void => {
  const calls = replayState.calls || [];
  callList.innerHTML = "";
  for (const call of calls) {
    const div = document.createElement("div");
    div.className = "callItem";
    const done = currentTime >= call.at;
    div.style.opacity = done ? "1" : "0.55";
    div.innerHTML = `<span>${call.at.toFixed(2)}s</span><span>${escapeHtml(call.content || "(pending recognizer output)")}</span><span class="badge ${call.kind}">${call.kind}</span>`;
    callList.appendChild(div);
  }
};

const renderTimelineMarks = (): void => {
  const calls = replayState.calls || [];
  timelineMarks.innerHTML = "";
  for (const call of calls) {
    const mark = document.createElement("span");
    mark.className = `mark ${call.kind}`;
    mark.style.left = `${Math.min(100, Math.max(0, (call.at / duration) * 100))}%`;
    mark.title = `${call.kind} OCR @ ${call.at.toFixed(2)}s`;
    timelineMarks.appendChild(mark);
  }
};

declare const katex: {
  renderToString(tex: string, options?: Record<string, unknown>): string;
};

const renderLatex = (latex: string): string => {
  try {
    return katex.renderToString(latex, { throwOnError: false, displayMode: false });
  } catch {
    return escapeHtml(latex);
  }
};

const escapeHtml = (value: unknown): string =>
  String(value).replace(
    /[&<>'"]/g,
    (ch) =>
      (({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" } as Record<string, string>)[ch])
  );

let lastFetchWall = -Infinity;

const requestReplayState = (force?: boolean): void => {
  if (!force && playing && performance.now() - lastFetchWall < 180) return;
  lastFetchWall = performance.now();
  fetchReplayState(currentTime).catch((error: Error) => {
    modelView.textContent = `Failed to build replay state: ${error.message}`;
  });
};

const setTime = (time: number, force?: boolean): void => {
  currentTime = Math.max(0, Math.min(duration, time));
  timeline.value = String(currentTime);
  draw();
  requestReplayState(force);
};

const tick = (timestamp: number): void => {
  if (!playing) return;
  if (lastFrame == null) lastFrame = timestamp;
  const elapsed = ((timestamp - lastFrame) / 1000) * Number(speedSelect.value);
  lastFrame = timestamp;
  if (currentTime + elapsed >= duration) {
    playing = false;
    playPause.textContent = "Play";
    lastFrame = null;
    setTime(duration, true);
    return;
  }
  setTime(currentTime + elapsed);
  requestAnimationFrame(tick);
};

async function loadFixture(name: string): Promise<void> {
  const response = await fetch(`/api/fixture/${encodeURIComponent(name)}`);
  if (!response.ok) throw new Error(await response.text());
  fixture = prepareFixtureForDrawing((await response.json()) as RawFixture);
  duration = Math.max(1, ...fixture.strokes.strokes.map((stroke) => stroke.times.end)) + 1.5;
  timeline.min = "0";
  timeline.max = String(duration);
  timeline.step = "0.01";
  setupCanvas();
  await fetchReplayState(0);
  setTime(0);
}

async function init(): Promise<void> {
  const response = await fetch("/api/fixtures");
  fixtures = (await response.json()) as FixtureListItem[];
  fixtureSelect.innerHTML = "";
  for (const item of fixtures) {
    const option = document.createElement("option");
    option.value = item.name;
    option.textContent = `${item.name} (${item.strokeCount} strokes)`;
    fixtureSelect.appendChild(option);
  }
  if (fixtures.length) await loadFixture(fixtures[0].name);
}

fixtureSelect.addEventListener("change", () => loadFixture(fixtureSelect.value));
timeline.addEventListener("input", () => {
  playing = false;
  playPause.textContent = "Play";
  lastFrame = null;
  setTime(Number(timeline.value));
});
idleInput.addEventListener("input", () => {
  fetchReplayState(currentTime).catch((error: Error) => {
    modelView.textContent = `Failed to build replay state: ${error.message}`;
  });
});
gapInput.addEventListener("input", () => {
  gapValue.textContent = gapInput.value;
  draw();
  fetchReplayState(currentTime).catch((error: Error) => {
    modelView.textContent = `Failed to build replay state: ${error.message}`;
  });
});
playPause.addEventListener("click", () => {
  playing = !playing;
  playPause.textContent = playing ? "Pause" : "Play";
  lastFrame = null;
  if (playing) requestAnimationFrame(tick);
  else requestReplayState(true);
});
restart.addEventListener("click", () => {
  playing = false;
  playPause.textContent = "Play";
  lastFrame = null;
  setTime(0);
});

const underlineAtEvent = (event: MouseEvent): ClassifiedUnderline | undefined => {
  const rect = canvas.getBoundingClientRect();
  const width = fixture?.canvasInfo?.width || 612;
  const height = fixture?.canvasInfo?.height || 792;
  const cx = (event.clientX - rect.left) * (width / rect.width);
  const cy = (event.clientY - rect.top) * (height / rect.height);
  return classifiedUnderlines.find(
    (hit) => cx >= hit.x0 - 2 && cx <= hit.x1 + 2 && Math.abs(cy - hit.y) <= 8
  );
};

const REVEAL_STAGES = 3;
const REVEAL_STEP = 40;

let tooltipHit: ClassifiedUnderline | null = null;
let tooltipStage = 0;
let tooltipDelta = 0;

const confidenceColor = (value: number): string => `hsl(${Math.round(value * 120)} 65% 45%)`;
const confidencePercent = (value: number): string => `${Math.round(value * 100)}%`;

const tokenColumn = (token: TokenConfidence, stage: number): string => {
  const confidence = `<div class="tconf" style="color:${confidenceColor(token.confidence)}">${confidencePercent(token.confidence)}</div>`;
  const alternatives =
    stage >= 3 && token.alternatives.length
      ? `<div class="talts">${token.alternatives
          .map((alt) => `<div>${escapeHtml(alt.token)}<em>${confidencePercent(alt.confidence)}</em></div>`)
          .join("")}</div>`
      : "";
  return `<div class="tcol">${confidence}<div class="tchar">${escapeHtml(token.token)}</div>${alternatives}</div>`;
};

const autocompleteSection = (auto: Autocomplete): string => {
  const body = auto.suggestion
    ? escapeHtml(auto.suggestion)
    : `<span style="opacity:0.6">${escapeHtml(auto.reason || "no suggestion")}</span>`;
  return `<div class="autocomplete">→ ${body} <span class="badge math">${escapeHtml(auto.operation)}</span></div>`;
};

const tooltipSections = (hit: ClassifiedUnderline, stage: number): string => {
  const hasTokens = hit.tokens.length > 0;
  const overall = hasTokens
    ? `<span class="overall" style="color:${confidenceColor(hit.confidence)}">${confidencePercent(hit.confidence)}</span>`
    : "";
  const header = `<span class="kind ${hit.kind}">${hit.kind}</span>`;
  const output = hit.content ? escapeHtml(hit.content) : "(empty CTC output)";
  const contentBlock = `<pre>${output} ${overall}</pre>`;
  const rendered = hit.latex ? `<div class="rendered">${renderLatex(hit.latex)}</div>` : "";
  const autoBlock = stage >= 1 && hit.autocomplete ? autocompleteSection(hit.autocomplete) : "";
  const tokensBlock =
    stage >= 2 && hasTokens
      ? `<div class="tokens">${hit.tokens.map((token) => tokenColumn(token, stage)).join("")}</div>`
      : "";
  const hint = stage < REVEAL_STAGES && hasTokens ? `<div class="hint">scroll to reveal ▾</div>` : "";
  return `${header}${contentBlock}${rendered}${autoBlock}${tokensBlock}${hint}`;
};

const showOcrTooltip = (hit: ClassifiedUnderline, event: MouseEvent): void => {
  if (hit !== tooltipHit) {
    tooltipHit = hit;
    tooltipDelta = 0;
  }
  ocrTooltip.innerHTML = tooltipSections(hit, tooltipStage);
  ocrTooltip.hidden = false;
  ocrTooltip.style.left = `${event.clientX + 14}px`;
  ocrTooltip.style.top = `${event.clientY + 14}px`;
};

canvas.addEventListener("mousemove", (event) => {
  const hit = underlineAtEvent(event);
  canvas.style.cursor = hit ? "help" : "default";
  if (hit) showOcrTooltip(hit, event);
  else {
    ocrTooltip.hidden = true;
    tooltipHit = null;
  }
});
canvas.addEventListener("mouseleave", () => {
  ocrTooltip.hidden = true;
  tooltipHit = null;
});
canvas.addEventListener(
  "wheel",
  (event) => {
    if (!tooltipHit || ocrTooltip.hidden) return;
    event.preventDefault();
    tooltipDelta += event.deltaY;
    while (tooltipDelta >= REVEAL_STEP && tooltipStage < REVEAL_STAGES) {
      tooltipStage += 1;
      tooltipDelta -= REVEAL_STEP;
    }
    while (tooltipDelta <= -REVEAL_STEP && tooltipStage > 0) {
      tooltipStage -= 1;
      tooltipDelta += REVEAL_STEP;
    }
    tooltipDelta = Math.max(-REVEAL_STEP, Math.min(REVEAL_STEP, tooltipDelta));
    ocrTooltip.innerHTML = tooltipSections(tooltipHit, tooltipStage);
  },
  { passive: false }
);

window.addEventListener("resize", draw);

init().catch((error: Error) => {
  modelView.textContent = `Failed to load fixtures: ${error.message}`;
});

export {};
