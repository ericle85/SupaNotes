# Math constraints on the OCR log

Scope: OCR only. Autocomplete is not being built. Everything below is what the math
case demands of *recognition*; the autocomplete findings are parked at the bottom.

## 1. The merge guard is a LaTeX parse, not a confidence comparison

Part 1 flagged that union-merging can exceed the model's one-`=` cap. The tempting
OCR-only guard is "merge if the union's CTC confidence beats the parts'." That does not
work: CTC will happily emit two `=` at high confidence and the cap truncates silently.
Confidence cannot see a structural violation.

The check that can is already written —
`translate_ctc_line_to_sympy` raises `TranslationError` on `count("=") > 1`
(`autocomplete/ctc_to_autosuggest_translator.py:73`).

> **Merge guard.** Merge only if the union still parses. If the union raises and the
> parts did not, keep them separate.

This is the one place OCR needs sympy. The function is a pure LaTeX→sympy parse with no
autocomplete dependencies, so importing it from `ocr_pipeline` is one import. It is
misfiled under `autocomplete/` given it is now shared — move it when that starts to
grate, not before.

Implemented in `recognition_log.merge_is_allowed`, driven by
`latex_validation.latex_parses`.

Correction to an earlier claim here: the guard does **not** refuse `2x=4` + `2`.
`2x=4 2` parses fine as `Eq(2*x, 42)`. That is unavoidable and mostly desirable — it is
the same mechanism that makes the common case work, where `2+3=` and a later `5` merge
into `Eq(2+3, 5)`. Nothing in the text can distinguish a continuation from an unrelated
neighbour; only the adjacency thresholds can. What the guard does reliably catch is the
two-`=` union and unparseable constructs.

Build this first. It carries most of the design.

## 2. `ink` has to be geometric — confidence cannot see a drawing

`route_group` (`recognizer.py`) already returns math vs text. The plan was to add `ink`
as a third bucket below a confidence gate. **Measured against the fixtures, that does
not work.** The drawn vertical line in `2_lines_math_and_line_on_right` decodes as `'1'`
at **confidence 1.000**. The model is not uncertain about drawings; it is confidently
wrong. No confidence threshold separates the two classes.

What does separate them is bbox shape. That line is 4.5 × 107 px — aspect ratio 0.04.
Across every fixture, the widest legitimate writing runs about 7.0 and nothing else
falls below 1.0.

> **Ink rule** (`recognizer.looks_like_drawing`). Aspect ratio below
> `INK_ASPECT_RATIO_MIN` (0.15) or above `INK_ASPECT_RATIO_MAX` (25.0), or a span under
> `INK_MINIMUM_SPAN_PX` (6.0), is a drawing. Checked before decode, so drawings never
> reach the model.

Measured headroom is 7.0 observed vs 25.0 gate, so long single-line math is safe — but
these are three tuning knobs, not physical constants. Handwriting varies per person and
per stylus. Expect to retune against real pages.

Known gap: a slash, a long division bar, or a hand-drawn `1` is geometrically a sliver
and will be classified ink. Nothing in the current fixtures exercises that.

## 3. There is no beam search — but the alternatives are already computed and discarded

I said the top-k parseability filter was the highest accuracy-per-effort item, gated on
whether the decoder exposes candidates. Checked: **it does not.** `collapse_with_confidence`
is greedy argmax (`recognizer.py:102`). No whole-sequence hypotheses exist.

But `step_alternatives` (`recognizer.py:89`) already runs `torch.topk` per timestep, and
every emitted token carries an `alternatives` list (`recognizer.py:112`). Nothing reads
it. Grep finds one producer, zero consumers.

That changes the recommendation from "add beam search" to:

> **Candidate re-ranking.** For the lowest-confidence token positions, substitute the
> runner-up from `alternatives`, and keep the first variant that parses.

Handwriting misreads are usually one token — `3`/`8`, `x`/`×`, `1`/`l`, `0`/`O`. A
one-token swap over the few weakest positions covers the common case in ~10 candidate
strings, each a cheap parse. No new dependency, and the raw material is already on the
wire.

Real CTC beam search (`torchaudio.models.decoder.ctc_decoder`, `pyctcdecode`) is a
dependency plus a rewrite of the decode path, for the multi-token-error tail. Not now.

Applies to math entries only. A parse failure on `kind: text` means nothing.

## 4. Multi-line math is out of scope, and the code already enforces it

`_UNSUPPORTED_CONSTRUCT` (`ctc_to_autosuggest_translator.py:14`) rejects matrices,
`\begin{...}`, set notation, and `\nabla`. With the model's one-line cap, every
multi-line construct — systems of equations, long division, aligned derivations —
fails to parse.

Consequence for OCR: those entries never merge (guard refuses) and get no candidate
re-ranking. They land in the log as their raw greedy decode. Correct for now, but it
means the log will contain known-bad text for this class of input. Do not treat a
low-confidence entry as a bug report.

## Build order — all five done

1. Deleted `render_spatial_text` and `spatialText`; no consumer existed
2. Append-only log in `ocr_pipeline/recognition_log.py`, built by
   `replay.build_recognition_log`
3. Merge rule: adjacency → re-OCR union → guard by parse
4. `ink` via geometry, not confidence (section 2)
5. Candidate re-ranking in `recognizer.reranked_tokens`

Verified on fixtures: `f(x)=` then `2x+3` merges to `f(x)=2x+3` superseding the
fragment; `16\theta-` re-OCRs as `160-2=` on the union; the drawn line drops to `ink`
and out of blocks. Existing suite is 61 passed, 2 failed, and both failures predate this
work — `tests/test_ocr_pipeline_cases.py` loads fixture `case_20260721_012208`, which is
not in `fixtures/`.

## Parked until autocomplete

- **Chain segmentation** by vertical gap + left-edge alignment. Needed because
  `_definitions_from_preceding` (`math_engine/engine.py:52`) substitutes from every
  preceding `x = <number>`, so margin scratch work from a different problem silently
  poisons the current one. A real bug, but only reachable through autocomplete.
  Recoverable any time from the stored bboxes.
- **Algebraic consistency check** across chain entries as an OCR error detector.
  Needs chain segmentation.
- **Suggestion placement** — three cases keyed on `kind` and `has_trailing_equals`.
- **Dead intent classifier.** `generate_next_line` ignores its `intent` argument
  (`engine.py:37-40`); the pipeline computes `classify_intent` and discards the result.
  `autocomplete/intent_classifier.py` is 12 dead lines. Delete when touching that path.
