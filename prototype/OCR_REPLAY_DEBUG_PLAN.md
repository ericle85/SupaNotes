# OCR Replay Debug Plan

The fixture replay harness treats recorded strokes as the source of truth for an end-to-end local OCR pipeline. A replay is a deterministic substitute for a live iPad writing session: every stroke has a stable id, point timestamps, bbox, and page-coordinate geometry.

## Trigger timing

Start with an idle trigger per spatial line group:

- collect completed strokes chronologically
- group completed strokes into spatial line candidates
- when a group has received no new stroke for `idleTriggerSeconds` (default 0.8s), enqueue OCR for that group
- if a later stroke joins the same group, enqueue a replacement OCR pass for the expanded group

This matches how handwriting feels: users write a line, pause, and only then expect recognition. The trigger should be debounced and cancellable; OCR results are provisional until the line has stayed unchanged for another short window.

## Page context model

Keep three layers separate:

1. `InkLayer`: raw strokes, stroke ids, timestamps, tool, bbox, and tombstone/delete state.
2. `RecognitionLayer`: OCR jobs and results for stroke groups. Jobs point to stroke ids, not pixels.
3. `SpatialDocument`: ordered text/math blocks with bbox, recognized text/latex, confidence, source, and the stroke ids that produced them.

Autocomplete should consume `SpatialDocument`, not raw OCR strings. A Markdown/text export is a projection of the spatial model.

## Grouping strokes into OCR chunks

Initial grouping can be line-based:

- group by vertical proximity / baseline overlap
- split by large vertical gaps first
- within a line, keep horizontally distant words/equation parts together until the idle trigger fires
- classify each group as text/math after grouping

Math OCR should usually operate on one equation line at a time because the CTC model has a one-equals-sign constraint. Multi-line derivations should become multiple math blocks.

## Erasing and partial erasing

Do not mutate old strokes in place. Use versioned ink events:

- `addStroke(strokeId)`
- `eraseStroke(strokeId)` for whole-stroke eraser
- `splitStroke(originalId, keptFragments)` for partial eraser

Any recognition block that references an erased/split stroke becomes stale. The scheduler should invalidate that block and enqueue OCR for affected neighboring groups. The spatial document should keep stable block ids where possible, but update their `revision` and source stroke ids.

## Debug overlays

The replay debugger should show:

- live stroke playback on a mock white page
- pending groups with dashed gray underlines
- text groups with blue underlines
- math groups with red underlines
- OCR call times on the timeline
- live `SpatialDocument` JSON as the replay time changes

The current prototype uses fixture truth/templates to stand in for recognizer output. Later, the server can add `/api/ocr/math` and `/api/ocr/text` endpoints to invoke CTC and Vision adapters.
