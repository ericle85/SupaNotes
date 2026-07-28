type Kind = "math" | "text" | "not labeled";

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

interface GhostText {
  text: string;
  placement: "left" | "right";
}

interface Autocomplete {
  operation: string;
  suggestion: string;
  reason: string;
  ghostText?: GhostText | null;
}

interface Block {
  strokes: string[];
  kind: Kind;
  bbox: Bbox;
  latex?: string;
  text?: string;
  autocomplete?: Autocomplete | null;
}

interface OcrCall {
  index: number;
  at: number;
  kind: Kind;
  content: string;
  bbox?: Bbox;
  bboxes?: Bbox[];
  strokes?: string[];
}

interface ReplayState {
  completedStrokeCount: number;
  totalStrokeCount: number;
  groups: Group[];
  blocks: Block[];
  calls: OcrCall[];
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
const toggleBoxes = byId<HTMLButtonElement>("toggleBoxes");
let showBoxes = false;
const speedSelect = byId<HTMLSelectElement>("speedSelect");
const idleInput = byId<HTMLInputElement>("idleInput");
const timeline = byId<HTMLProgressElement>("timeline");
const canvas = byId<HTMLCanvasElement>("canvas");
const ctx = canvas.getContext("2d") as CanvasRenderingContext2D;
const timeValue = byId<HTMLDivElement>("timeValue");
const strokeValue = byId<HTMLDivElement>("strokeValue");
const groupValue = byId<HTMLDivElement>("groupValue");
const blockValue = byId<HTMLDivElement>("blockValue");
const spatialPage = byId<HTMLDivElement>("spatialPage");
const callList = byId<HTMLDivElement>("callList");
const autocompleteList = byId<HTMLDivElement>("autocompleteList");
const ocrTooltip = byId<HTMLDivElement>("ocrTooltip");

let classifiedUnderlines: ClassifiedUnderline[] = [];
let selectedOcrCallIndex: number | null = null;

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

const emptyReplayState = (totalStrokeCount = 0): ReplayState => ({
  completedStrokeCount: 0,
  totalStrokeCount,
  groups: [],
  blocks: [],
  calls: [],
  document: {},
});

let replayState: ReplayState = emptyReplayState();
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
  ({ math: colors.math, text: colors.text, "not labeled": colors.pending } as Record<Kind, string>)[kind] ||
  colors.pending;

async function fetchReplayState(time: number, reset = false): Promise<void> {
  if (!fixture) return;
  const serial = ++stateRequestSerial;
  const idleSeconds = Number(idleInput.value) || 0.8;
  const name = fixtures.find((item) => item.name === fixtureSelect.value)?.name ?? fixtureSelect.value;
  const url = `/api/replay_state/${encodeURIComponent(name)}?time=${encodeURIComponent(time.toFixed(3))}&idle=${encodeURIComponent(idleSeconds)}${reset ? "&reset=1" : ""}`;
  const response = await fetch(url);
  if (!response.ok) throw new Error(await response.text());
  const nextState = (await response.json()) as ReplayState;
  if (serial === stateRequestSerial) {
    replayState = nextState;
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

const drawGhostText = (bbox: Bbox, ghost: GhostText): void => {
  const [gx0, gy0, gx1, gy1] = bbox;
  const midY = (gy0 + gy1) / 2;
  ctx.save();
  ctx.font = "22px ui-sans-serif, system-ui";
  ctx.fillStyle = colors.math;
  ctx.globalAlpha = 0.4;
  ctx.textBaseline = "middle";
  if (ghost.placement === "left") {
    ctx.textAlign = "right";
    ctx.fillText(ghost.text, gx0 - 8, midY);
  } else {
    ctx.textAlign = "left";
    ctx.fillText(ghost.text, gx1 + 8, midY);
  }
  ctx.restore();
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
    called ? `${group.kind} OCR` : `OCR pending ${remaining.toFixed(1)}s`,
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
    const ghost = block?.autocomplete?.ghostText;
    if (ghost) drawGhostText(group.bbox, ghost);
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


const bboxesForCall = (call: OcrCall): Bbox[] => {
  if (call.bboxes?.length) return call.bboxes;
  return call.bbox ? [call.bbox] : [];
};

const drawSelectedOcrCallBoxes = (): void => {
  if (selectedOcrCallIndex == null) return;
  const call = replayState.calls.find((candidate) => candidate.index === selectedOcrCallIndex);
  if (!call) return;

  ctx.save();
  ctx.strokeStyle = kindColor(call.kind);
  ctx.lineWidth = 2;
  ctx.setLineDash([4, 3]);
  for (const bbox of bboxesForCall(call)) {
    const [x0, y0, x1, y1] = bbox;
    ctx.strokeRect(x0, y0, x1 - x0, y1 - y0);
  }
  ctx.restore();
};

const renderSpatialPage = (): void => {
  const cw = fixture?.canvasInfo?.width || 612;
  const ch = fixture?.canvasInfo?.height || 792;
  spatialPage.style.aspectRatio = `${cw} / ${ch}`;
  spatialPage.innerHTML = "";

  const recognized = replayState.blocks.filter(
    (block) => block.kind === "math" || block.kind === "text"
  );
  if (!recognized.length) return;

  for (const block of recognized) {
    const [x0, y0, , y1] = block.bbox;
    const content = block.latex || block.text || "";
    if (!content) continue;

    const span = document.createElement("span");
    span.textContent = content;
    span.style.position = "absolute";
    span.style.left = `${(x0 / cw) * 100}%`;
    span.style.top = `${(((y0 + y1) / 2) / ch) * 100}%`;
    span.style.transform = "translateY(-50%)";
    span.style.fontSize = "12px";
    span.style.fontFamily = "monospace";
    span.style.whiteSpace = "pre";
    span.style.color = kindColor(block.kind as Kind);
    spatialPage.appendChild(span);
  }
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
    const called = calledKeys.has(group.strokes.join("|"));
    drawUnderline(group, called);
    if (showBoxes) {
      const [bx0, by0, bx1, by1] = group.bbox;
      ctx.save();
      ctx.strokeStyle = called ? kindColor(group.kind) : colors.pending;
      ctx.lineWidth = 2;
      ctx.setLineDash([4, 3]);
      ctx.strokeRect(bx0, by0, bx1 - bx0, by1 - by0);
      ctx.restore();
    }
  }
  drawSelectedOcrCallBoxes();

  timeValue.textContent = `${currentTime.toFixed(2)}s / ${duration.toFixed(2)}s`;
  strokeValue.textContent = `${replayState.completedStrokeCount} / ${replayState.totalStrokeCount}`;
  groupValue.textContent = String(replayState.groups.length);
  blockValue.textContent = String(replayState.blocks.length);
  renderSpatialPage();
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
  if (!calls.length) {
    callList.innerHTML = `<div class="callItem" style="opacity:0.55"><span>—</span><span>no replayed OCR yet</span><span></span></div>`;
    return;
  }
  for (const call of calls) {
    const div = document.createElement("div");
    const selected = selectedOcrCallIndex === call.index;
    div.className = `callItem selectable${selected ? " selected" : ""}`;
    div.tabIndex = 0;
    div.setAttribute("role", "button");
    div.setAttribute("aria-pressed", String(selected));
    div.title = "Toggle the CTC input bounding box for this inference";
    div.innerHTML = `<span>${call.at.toFixed(2)}s</span><span>${escapeHtml(call.content || "(empty CTC output)")}</span><span class="badge ${call.kind}">${call.kind}</span>`;
    const toggle = (): void => {
      selectedOcrCallIndex = selectedOcrCallIndex === call.index ? null : call.index;
      draw();
    };
    div.addEventListener("click", toggle);
    div.addEventListener("keydown", (event) => {
      if (event.key !== "Enter" && event.key !== " ") return;
      event.preventDefault();
      toggle();
    });
    callList.appendChild(div);
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
let replayStateFetchInFlight = false;

const requestReplayState = (force?: boolean): void => {
  if (!force && playing && performance.now() - lastFetchWall < 180) return;
  if (!force && replayStateFetchInFlight) return;
  lastFetchWall = performance.now();
  replayStateFetchInFlight = true;
  fetchReplayState(currentTime)
    .catch((error: Error) => {
      spatialPage.textContent = `Failed to build replay state: ${error.message}`;
    })
    .finally(() => {
      replayStateFetchInFlight = false;
    });
};

const setTime = (time: number, force?: boolean): void => {
  currentTime = Math.max(0, Math.min(duration, time));
  timeline.value = currentTime;
  draw();
  requestReplayState(force);
};

const tick = (timestamp: number): void => {
  if (!playing) return;
  if (replayStateFetchInFlight) {
    // Debugger mode: hold replay time while OCR/replay-state work is running.
    // This makes model latency visible as a UI stutter instead of letting the
    // timeline advance and enqueue/skip overlapping inference snapshots.
    lastFrame = timestamp;
    requestAnimationFrame(tick);
    return;
  }
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
  playing = false;
  playPause.textContent = "Play";
  lastFrame = null;
  currentTime = 0;
  timeline.max = duration;
  timeline.value = 0;
  replayState = emptyReplayState(fixture.strokes.strokes.length);
  classifiedUnderlines = [];
  selectedOcrCallIndex = null;
  stateRequestSerial += 1;
  setupCanvas();
  draw();
  await fetchReplayState(0, true);
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
idleInput.addEventListener("input", () => {
  fetchReplayState(currentTime).catch((error: Error) => {
    spatialPage.textContent = `Failed to build replay state: ${error.message}`;
  });
});
playPause.addEventListener("click", () => {
  playing = !playing;
  playPause.textContent = playing ? "Pause" : "Play";
  lastFrame = null;
  if (playing) requestAnimationFrame(tick);
  else requestReplayState(true);
});
toggleBoxes.addEventListener("click", () => {
  showBoxes = !showBoxes;
  toggleBoxes.textContent = showBoxes ? "Boxes: on" : "Boxes: off";
  toggleBoxes.setAttribute("aria-pressed", String(showBoxes));
  draw();
});
restart.addEventListener("click", () => {
  playing = false;
  playPause.textContent = "Play";
  lastFrame = null;
  currentTime = 0;
  timeline.value = 0;
  replayState = emptyReplayState(fixture?.strokes.strokes.length ?? 0);
  selectedOcrCallIndex = null;
  draw();
  fetchReplayState(0, true).catch((error: Error) => {
    spatialPage.textContent = `Failed to reset replay state: ${error.message}`;
  });
});

const eventToCanvas = (event: MouseEvent): { x: number; y: number } => {
  const rect = canvas.getBoundingClientRect();
  const width = fixture?.canvasInfo?.width || 612;
  const height = fixture?.canvasInfo?.height || 792;
  return {
    x: (event.clientX - rect.left) * (width / rect.width),
    y: (event.clientY - rect.top) * (height / rect.height),
  };
};

const underlineAtEvent = (event: MouseEvent): ClassifiedUnderline | undefined => {
  const { x: cx, y: cy } = eventToCanvas(event);
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
  spatialPage.textContent = `Failed to load fixtures: ${error.message}`;
});

export {};
