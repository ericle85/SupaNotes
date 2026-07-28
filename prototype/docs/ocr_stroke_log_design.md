# OCR stroke log (replaces spatial text)

## Verdict on the proposal

Direction is right. Four corrections.

## 1. Scrap the serialization, keep the geometry

Delete `render_spatial_text` (`ocr_pipeline/grouping.py:146`) and `spatialText`
(`ocr_pipeline/replay.py:308`). The ASCII-art page is dead weight for the reason given:
column padding does not survive contact with a real handwritten page.

But bboxes stay. They are load-bearing for two things:
- the merge rule (section 3)
- reading order, if ever needed: sort entries into y-bands, then by x. That is
  a fold over the log, not stored state. Recoverable any time, so do not build it now.

## 2. It is a log, not a stack

Nothing is ever popped. Calling it a stack invites a push/pop API that cannot express
revision. Append-only log; the current document is a fold over it.

Entry:

    id
    strokeIds      -> lets a better model re-OCR history later
    bbox
    text
    kind           -> math | text | ink
    confidence
    supersedes     -> [id]

`kind: ink` is the drawing/arrow bucket, decided by bbox geometry — see the math notes,
section 2. Keep the entry, exclude it from blocks. Do not discard the strokes.

`supersedes` is how correction works. No mutation, no deletion, undo is free.

## 3. One merge rule covers both cases

The proposal treats "wrote on top of something" as a special case. It is not — it is the
same rule as the mid-thought idle split, which is the more common failure:

> Pause to think in the middle of `x^2 + 3x`. Idle fires. CTC gets `x^2 +` and `3x`
> as two entries, and the fragment OCR is garbage.

Single rule, both cases:

    new strokes at idle
      -> find entries whose bbox overlaps or is horizontally adjacent
      -> if any: re-OCR the union of stroke sets
      -> append entry with supersedes = [those ids]
      -> else: append plain

Erase goes through the same path. Erasing strokes out of a merged entry means re-OCR
the remainder and append a superseder — `erased_stroke_ids_at` already gives the
stroke ids (`replay.py:80`).

## 4. Guard the merge against the CTC ceiling

The model caps at one `=` per line. Union-merging two adjacent entries can produce two,
which silently truncates. Merge needs a bail-out: if the union recognizes worse than the
parts (lower confidence, or `=` count over cap), keep them separate.

This is the one place that needs a real check, since it is the failure the log cannot
represent.

## Text recognition stand-in

Text blocks were empty because nothing recognized English — the CTC is math-only and
`block_from_group` stamped `source: "apple_vision_pending"`. The frontend was always
fine; `renderSpatialPage` does `block.latex || block.text` and skips empty content.

`handwriting_text_recognizer.py` fills the gap: rasterize the group's strokes to a PNG
and run Apple Vision's `VNRecognizeTextRequest`. Native, offline, already installed via
pyobjc, and the same vendor as the eventual iPad path.

Quality on the fixtures is usable but not clean — "Hello **Warld** this is a test to See
**now** good english", "Solve **far** X". Fine for pipeline work, not for judging
autocomplete quality.

Alternatives considered:

- **TrOCR** (`microsoft/trocr-base-handwritten`) — image-based like Vision, ~330MB,
  cross-platform. Worth trying only if Vision's error rate blocks something.
- **Google Input Tools handwriting endpoint** — genuinely stroke-based, takes raw
  coordinates. Undocumented, and it ships the user's handwriting to Google. Rejected on
  privacy for a notes app.
- **MyScript iink** — the commercial standard for online (stroke-based) recognition.
  Real option if stroke-level English matters later; costs money.
- **Train the existing `CTCTransformer` on IAM-OnDB** — the architecturally aligned
  answer: same model, same preprocessing, English vocab instead of LaTeX. That is a
  training project, not a stand-in.

Rasterizing discards stroke order and timing, which is exactly what an online recognizer
would use. That is the accepted cost of the shortcut; the strokes stay in the log, so
swapping in a real stroke-based recognizer later needs no data migration.

## Deliberately not doing

- **Spatial index.** Linear scan of bboxes. A page is tens of entries; an R-tree is
  microseconds saved against hours spent. `ponytail: O(n) bbox scan per idle fire,
  index it if a page ever holds thousands of entries`.
- **Reading order.** Chronological is correct for cursor-local autocomplete, which is
  the actual use case — the last N entries *are* the context. It is wrong for
  whole-page tasks (summarize, solve the problem set). Add the y-band sort when a
  whole-page feature exists, not before.
- **Suggestion placement.** Top-of-log bbox, right edge, same baseline. Hardcode it.
